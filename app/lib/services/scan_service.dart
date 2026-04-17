import 'dart:io';

import 'package:flutter/material.dart';

import '../models/document_record.dart';
import '../ui/custom_scanner_screen.dart';
import 'pdf_service.dart';

class ScanService {
  ScanService({PdfService? pdfService})
    : _pdfService = pdfService ?? PdfService();

  final PdfService _pdfService;

  Future<DocumentRecord?> scanAndCreatePdf({
    required BuildContext context,
    required PdfColorMode mode,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw const ScanFlowException(
        'This scanner flow is currently available on Android and iPhone.',
      );
    }

    try {
      final imagePaths = await CustomScannerScreen.capture(context);
      if (imagePaths == null || imagePaths.isEmpty) {
        return null;
      }

      return _pdfService.createA4Pdf(sourceImagePaths: imagePaths, mode: mode);
    } on Exception catch (error) {
      throw ScanFlowException(error.toString());
    }
  }
}

class ScanFlowException implements Exception {
  const ScanFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
