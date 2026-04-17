import 'dart:convert';

enum PdfColorMode { color, grayscale, blackWhite }

extension PdfColorModeX on PdfColorMode {
  String get label => switch (this) {
    PdfColorMode.color => 'Color PDF',
    PdfColorMode.grayscale => 'Gray PDF',
    PdfColorMode.blackWhite => 'B/W PDF',
  };

  String get shortLabel => switch (this) {
    PdfColorMode.color => 'Color',
    PdfColorMode.grayscale => 'Gray',
    PdfColorMode.blackWhite => 'B/W',
  };

  String get description => switch (this) {
    PdfColorMode.color => 'Natural colors with balanced compression.',
    PdfColorMode.grayscale => 'Smaller size with softer monochrome pages.',
    PdfColorMode.blackWhite => 'Sharp text-first output for documents.',
  };
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.folderPath,
    required this.pdfPath,
    required this.imagePaths,
    required this.pageCount,
    required this.fileSizeBytes,
    required this.mode,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String folderPath;
  final String pdfPath;
  final List<String> imagePaths;
  final int pageCount;
  final int fileSizeBytes;
  final PdfColorMode mode;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  Duration get timeLeft {
    final now = DateTime.now();
    if (!expiresAt.isAfter(now)) {
      return Duration.zero;
    }
    return expiresAt.difference(now);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'folderPath': folderPath,
      'pdfPath': pdfPath,
      'imagePaths': imagePaths,
      'pageCount': pageCount,
      'fileSizeBytes': fileSizeBytes,
      'mode': mode.name,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  factory DocumentRecord.fromMap(Map<String, dynamic> map) {
    return DocumentRecord(
      id: map['id'] as String,
      folderPath: map['folderPath'] as String,
      pdfPath: map['pdfPath'] as String,
      imagePaths: List<String>.from(map['imagePaths'] as List<dynamic>),
      pageCount: map['pageCount'] as int,
      fileSizeBytes: map['fileSizeBytes'] as int,
      mode: PdfColorMode.values.byName(map['mode'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      expiresAt: DateTime.parse(map['expiresAt'] as String),
    );
  }
}

String encodeDocumentRecords(List<DocumentRecord> records) {
  return jsonEncode(records.map((record) => record.toMap()).toList());
}

List<DocumentRecord> decodeDocumentRecords(String? source) {
  if (source == null || source.trim().isEmpty) {
    return const <DocumentRecord>[];
  }

  final decoded = jsonDecode(source) as List<dynamic>;
  return decoded
      .map((item) => DocumentRecord.fromMap(item as Map<String, dynamic>))
      .toList();
}

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kiloBytes = bytes / 1024;
  if (kiloBytes < 1024) {
    return '${kiloBytes.toStringAsFixed(kiloBytes < 10 ? 1 : 0)} KB';
  }

  final megaBytes = kiloBytes / 1024;
  return '${megaBytes.toStringAsFixed(megaBytes < 10 ? 1 : 0)} MB';
}

String formatRemaining(Duration duration) {
  if (duration <= Duration.zero) {
    return 'Expired';
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours > 0) {
    return '$hours h ${minutes.toString().padLeft(2, '0')} m left';
  }
  return '${duration.inMinutes} min left';
}
