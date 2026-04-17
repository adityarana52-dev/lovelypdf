import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'document_store.dart';

const String cleanupTaskName = 'docpdf.cleanup.expired.files';

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await DocumentStore.instance.cleanupExpired();
    return true;
  });
}

class BackgroundTasks {
  BackgroundTasks._();

  static bool _isReady = false;

  static Future<void> initialize() async {
    if (_isReady || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    await Workmanager().initialize(backgroundTaskDispatcher);

    await Workmanager().registerPeriodicTask(
      'docpdf-cleanup-worker',
      cleanupTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    _isReady = true;
  }
}
