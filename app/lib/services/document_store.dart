import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/document_record.dart';

class DocumentStore {
  DocumentStore._();

  static const String _storageKey = 'docpdf.saved_documents.v1';
  static final DocumentStore instance = DocumentStore._();

  Future<List<DocumentRecord>> loadDocuments() async {
    await cleanupExpired();
    final records = await _readRecords();
    records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return records;
  }

  Future<Directory> createWorkingDirectory(String documentId) async {
    final base = await _baseDirectory();
    final working = Directory(p.join(base.path, documentId));
    await working.create(recursive: true);
    return working;
  }

  Future<void> saveDocument(DocumentRecord record) async {
    final records = await _readRecords();
    final updated = <DocumentRecord>[
      record,
      ...records.where((item) => item.id != record.id),
    ];
    await _writeRecords(updated);
  }

  Future<void> deleteDocument(String documentId) async {
    final records = await _readRecords();
    final match = records.where((item) => item.id == documentId).toList();
    if (match.isNotEmpty) {
      await _deletePath(match.first.folderPath);
    }

    final updated = records.where((item) => item.id != documentId).toList();
    await _writeRecords(updated);
  }

  Future<int> cleanupExpired() async {
    final records = await _readRecords();
    final now = DateTime.now();
    final active = <DocumentRecord>[];
    var deletedCount = 0;

    for (final record in records) {
      if (record.expiresAt.isAfter(now)) {
        active.add(record);
        continue;
      }

      deletedCount += 1;
      await _deletePath(record.folderPath);
    }

    await _writeRecords(active);
    deletedCount += await _cleanupOrphanDirectories(active);
    return deletedCount;
  }

  Future<int> _cleanupOrphanDirectories(List<DocumentRecord> active) async {
    final base = await _baseDirectory();
    if (!await base.exists()) {
      return 0;
    }

    final activeFolders = active.map((item) => item.folderPath).toSet();
    final cutoff = DateTime.now().subtract(documentRetentionDuration);
    var removed = 0;

    await for (final entity in base.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      if (activeFolders.contains(entity.path)) {
        continue;
      }

      final modified = (await entity.stat()).modified;
      if (modified.isAfter(cutoff)) {
        continue;
      }

      removed += 1;
      await entity.delete(recursive: true);
    }

    return removed;
  }

  Future<List<DocumentRecord>> _readRecords() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeDocumentRecords(prefs.getString(_storageKey));
  }

  Future<void> _writeRecords(List<DocumentRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, encodeDocumentRecords(records));
  }

  Future<Directory> _baseDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final base = Directory(p.join(tempDir.path, 'docpdf_documents'));
    await base.create(recursive: true);
    return base;
  }

  Future<void> _deletePath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
        return;
      case FileSystemEntityType.file:
        await File(path).delete();
        return;
      case FileSystemEntityType.link:
        await Link(path).delete();
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        return;
      case FileSystemEntityType.notFound:
        return;
    }
  }
}
