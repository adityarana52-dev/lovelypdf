import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_config.dart';
import '../models/document_record.dart';
import 'document_store.dart';

class PdfService {
  PdfService({DocumentStore? store}) : _store = store ?? DocumentStore.instance;

  final DocumentStore _store;
  static const int _captureWorkingEdge = 2800;
  static const int _maxRenderedEdge = 2800;
  static const List<num> _sharpenKernel = <num>[0, -1, 0, -1, 5, -1, 0, -1, 0];

  Future<DocumentRecord> createA4Pdf({
    required List<String> sourceImagePaths,
    required PdfColorMode mode,
    String? sourcePdfPath,
    int? scannedPageCount,
  }) async {
    final createdAt = DateTime.now();
    final documentId = 'scan_${createdAt.microsecondsSinceEpoch}';
    final documentDir = await _store.createWorkingDirectory(documentId);
    final pdfPath = p.join(documentDir.path, 'LovelyPDF_$documentId.pdf');
    final shouldKeepScannerPdf =
        mode == PdfColorMode.color &&
        sourcePdfPath != null &&
        await File(sourcePdfPath).exists();

    List<String> preparedPaths = const <String>[];
    late final int pageCount;

    if (shouldKeepScannerPdf) {
      await File(sourcePdfPath).copy(pdfPath);
      pageCount = scannedPageCount ?? sourceImagePaths.length;
    } else {
      final pagesDir = Directory(p.join(documentDir.path, 'pages'));
      await pagesDir.create(recursive: true);

      preparedPaths = <String>[];
      for (var index = 0; index < sourceImagePaths.length; index += 1) {
        final pageNumber = (index + 1).toString().padLeft(2, '0');
        final bytes = await _prepareImageBytes(
          sourcePath: sourceImagePaths[index],
          mode: mode,
        );
        final outputPath = p.join(pagesDir.path, 'page_$pageNumber.jpg');
        await File(outputPath).writeAsBytes(bytes, flush: true);
        preparedPaths.add(outputPath);
      }

      await _writePdf(preparedPaths, pdfPath);
      pageCount = preparedPaths.length;
    }

    final pdfFile = File(pdfPath);
    final record = DocumentRecord(
      id: documentId,
      folderPath: documentDir.path,
      pdfPath: pdfPath,
      imagePaths: preparedPaths,
      pageCount: pageCount,
      fileSizeBytes: await pdfFile.length(),
      mode: mode,
      createdAt: createdAt,
      expiresAt: createdAt.add(documentRetentionDuration),
    );

    await _store.saveDocument(record);
    return record;
  }

  Future<Uint8List> _prepareImageBytes({
    required String sourcePath,
    required PdfColorMode mode,
  }) async {
    final sourceBytes = await _loadWorkingBytes(sourcePath, mode);
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return sourceBytes;
    }

    final resized = _resizeForPdf(decoded);
    final processed = _applyMode(resized, mode);
    final quality = switch (mode) {
      PdfColorMode.color => 93,
      PdfColorMode.grayscale => 91,
      PdfColorMode.blackWhite => 89,
    };

    return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
  }

  Future<Uint8List> _loadWorkingBytes(
    String sourcePath,
    PdfColorMode mode,
  ) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      sourcePath,
      quality: mode == PdfColorMode.color ? 96 : 94,
      minWidth: _captureWorkingEdge,
      minHeight: _captureWorkingEdge,
      format: CompressFormat.jpeg,
    );

    if (compressed != null && compressed.isNotEmpty) {
      return compressed;
    }

    return Uint8List.fromList(await File(sourcePath).readAsBytes());
  }

  img.Image _resizeForPdf(img.Image source) {
    final longestEdge = math.max(source.width, source.height);
    if (longestEdge <= _maxRenderedEdge) {
      return source;
    }

    final scale = _maxRenderedEdge / longestEdge;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  img.Image _applyMode(img.Image image, PdfColorMode mode) {
    final enhanced = _enhanceForPdf(image, mode);

    return switch (mode) {
      PdfColorMode.color => enhanced,
      PdfColorMode.grayscale => img.grayscale(enhanced),
      PdfColorMode.blackWhite => img.luminanceThreshold(
        img.grayscale(enhanced),
        threshold: 0.64,
      ),
    };
  }

  img.Image _enhanceForPdf(img.Image image, PdfColorMode mode) {
    final adjusted = img.adjustColor(
      img.normalize(image.clone(), min: 0, max: 255),
      contrast: switch (mode) {
        PdfColorMode.color => 1.05,
        PdfColorMode.grayscale => 1.08,
        PdfColorMode.blackWhite => 1.12,
      },
      brightness: 1.02,
      gamma: 0.98,
      saturation: mode == PdfColorMode.color ? 1.02 : 1.0,
    );

    return img.convolution(
      adjusted,
      filter: _sharpenKernel,
      amount: switch (mode) {
        PdfColorMode.color => 0.28,
        PdfColorMode.grayscale => 0.42,
        PdfColorMode.blackWhite => 0.58,
      },
    );
  }

  Future<void> _writePdf(List<String> imagePaths, String outputPath) async {
    const pageMargin = 20.0;
    final document = pw.Document(
      title: 'LovelyPDF Scan',
      author: 'LovelyPDF',
      creator: 'LovelyPDF',
    );

    for (final imagePath in imagePaths) {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        continue;
      }

      final availableWidth = PdfPageFormat.a4.width - (pageMargin * 2);
      final availableHeight = PdfPageFormat.a4.height - (pageMargin * 2);
      final imageAspectRatio = decoded.width / decoded.height;
      final pageAspectRatio = availableWidth / availableHeight;

      late final double renderWidth;
      late final double renderHeight;

      if (imageAspectRatio > pageAspectRatio) {
        renderWidth = availableWidth;
        renderHeight = renderWidth / imageAspectRatio;
      } else {
        renderHeight = availableHeight;
        renderWidth = renderHeight * imageAspectRatio;
      }

      final provider = pw.MemoryImage(bytes);

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(pageMargin),
          build: (context) {
            return pw.Center(
              child: pw.SizedBox(
                width: renderWidth,
                height: renderHeight,
                child: pw.Image(provider, fit: pw.BoxFit.contain),
              ),
            );
          },
        ),
      );
    }

    await File(outputPath).writeAsBytes(await document.save(), flush: true);
  }
}
