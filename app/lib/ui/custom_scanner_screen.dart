import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/scan_quality_service.dart';
import 'scan_edit_screen.dart';

class CustomScannerScreen extends StatefulWidget {
  const CustomScannerScreen({super.key});

  static Future<List<String>?> capture(BuildContext context) {
    return Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => const CustomScannerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<CustomScannerScreen> createState() => _CustomScannerScreenState();
}

class _CustomScannerScreenState extends State<CustomScannerScreen>
    with WidgetsBindingObserver {
  static const Duration _focusIndicatorDuration = Duration(milliseconds: 900);
  static const Duration _focusSettleDelay = Duration(milliseconds: 280);

  final ScanQualityService _qualityService = const ScanQualityService();
  final List<String> _acceptedPages = <String>[];

  CameraController? _controller;
  CameraDescription? _selectedCamera;
  FlashMode _flashMode = FlashMode.off;
  Offset? _focusIndicatorPosition;
  String? _reviewImagePath;
  ScanQualityAssessment? _reviewQuality;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _didFinish = false;
  DateTime? _lastFocusAt;
  Timer? _focusIndicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusIndicatorTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    if (!_didFinish) {
      for (final path in <String>[
        ..._acceptedPages,
        ...?_reviewImagePath == null ? null : <String>[_reviewImagePath!],
      ]) {
        unawaited(_deleteFile(path));
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_reviewImagePath != null) {
      return;
    }

    final camera = _selectedCamera;
    final controller = _controller;
    if (camera == null || controller == null) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller = null;
      unawaited(controller.dispose());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_startCamera(camera));
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'camera_unavailable',
          'No camera was found on this device.',
        );
      }

      final preferred = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final selected = preferred.isNotEmpty ? preferred.first : cameras.first;
      _selectedCamera = selected;
      await _startCamera(selected);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = 'The camera could not start. Please try again.';
      });
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final previous = _controller;
    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(_flashMode);

      await previous?.dispose();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } on CameraException catch (error) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    }
  }

  String _cameraErrorMessage(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' => 'Allow camera access to use the scanner.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Enable camera access from device settings.',
      'CameraAccessRestricted' => 'Camera access is restricted on this device.',
      _ => error.description ?? 'The camera could not be opened.',
    };
  }

  Future<void> _handlePreviewTap(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _reviewImagePath != null) {
      return;
    }

    final normalizedPoint = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );

    setState(() {
      _focusIndicatorPosition = details.localPosition;
    });
    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(_focusIndicatorDuration, () {
      if (mounted) {
        setState(() {
          _focusIndicatorPosition = null;
        });
      }
    });

    try {
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(normalizedPoint);
      }
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(normalizedPoint);
      }
      _lastFocusAt = DateTime.now();
    } on CameraException {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Focus could not be set. Tap again to retry.';
      });
    }
  }

  Future<void> _capturePage() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _reviewImagePath != null) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final shouldRefocus =
          _lastFocusAt == null ||
          now.difference(_lastFocusAt!) > const Duration(seconds: 2);
      if (shouldRefocus) {
        const center = Offset(0.5, 0.5);
        if (controller.value.exposurePointSupported) {
          await controller.setExposurePoint(center);
        }
        if (controller.value.focusPointSupported) {
          await controller.setFocusPoint(center);
        }
        await Future<void>.delayed(_focusSettleDelay);
      }

      final file = await controller.takePicture();
      await controller.pausePreview();
      final quality = await _qualityService.assessImage(file.path);

      if (!mounted) {
        return;
      }

      setState(() {
        _reviewImagePath = file.path;
        _reviewQuality = quality;
        _isCapturing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCapturing = false;
        _errorMessage = error.description ?? 'The photo could not be captured.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCapturing = false;
        _errorMessage = 'The photo could not be captured.';
      });
    }
  }

  Future<void> _retakePage() async {
    final path = _reviewImagePath;
    setState(() {
      _reviewImagePath = null;
      _reviewQuality = null;
    });
    if (path != null) {
      await _deleteFile(path);
    }
    await _controller?.resumePreview();
  }

  Future<void> _editReviewPage() async {
    final path = _reviewImagePath;
    if (path == null) {
      return;
    }

    final editedPath = await ScanEditScreen.edit(context, path);
    if (editedPath == null || !mounted) {
      return;
    }

    final quality = await _qualityService.assessImage(editedPath);
    if (!mounted) {
      return;
    }

    await _deleteFile(path);
    setState(() {
      _reviewImagePath = editedPath;
      _reviewQuality = quality;
    });
  }

  Future<void> _acceptPage({required bool finish}) async {
    final path = _reviewImagePath;
    if (path == null) {
      return;
    }

    _acceptedPages.add(path);

    if (finish) {
      _didFinish = true;
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pop<List<String>>(List<String>.from(_acceptedPages));
      return;
    }

    setState(() {
      _reviewImagePath = null;
      _reviewQuality = null;
    });
    await _controller?.resumePreview();
  }

  Future<void> _finishWithCapturedPages() async {
    if (_acceptedPages.isEmpty) {
      Navigator.of(context).pop<List<String>?>(null);
      return;
    }

    _didFinish = true;
    Navigator.of(context).pop<List<String>>(List<String>.from(_acceptedPages));
  }

  Future<void> _cycleFlashMode() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };

    try {
      await controller.setFlashMode(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _flashMode = next;
      });
    } on CameraException {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'The flash mode could not be changed.';
      });
    }
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: const Color(0xFF090B0D),
        body: SafeArea(
          child: _reviewImagePath != null
              ? _buildReview(context)
              : _buildCamera(context),
        ),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;

    if (_errorMessage != null && controller == null) {
      return _ScannerErrorView(
        message: _errorMessage!,
        onClose: () => Navigator.of(context).pop<List<String>?>(null),
        onRetry: () => unawaited(_initializeCamera()),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: <Widget>[
              _TopIconButton(
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop<List<String>?>(null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap to focus scanner',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_acceptedPages.isNotEmpty)
                _CountChip(label: '${_acceptedPages.length} pages'),
              const SizedBox(width: 8),
              _TopIconButton(
                icon: _flashIcon(_flashMode),
                onPressed: _cycleFlashMode,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Center(child: _buildPreviewCard()),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFFFC7C2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            children: <Widget>[
              Text(
                'Tap on the document to focus, then capture the page.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD6E1E0),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _acceptedPages.isEmpty
                          ? null
                          : _finishWithCapturedPages,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF325059)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: _isInitializing ? null : _capturePage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isCapturing
                            ? const Color(0xFF3B5260)
                            : const Color(0xFFF4B66A),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: _isCapturing || _isInitializing
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Color(0xFF101418),
                                ),
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF161B20),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      _acceptedPages.isEmpty
                          ? 'Capture your first page'
                          : 'You can add more pages',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFBFD0CF),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    final controller = _controller;
    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF12171C),
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFF4B66A)),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AspectRatio(
        aspectRatio: 1 / controller.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (details) => _handlePreviewTap(details, constraints),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CameraPreview(controller),
                  const _DocumentFrameOverlay(),
                  if (_focusIndicatorPosition != null)
                    Positioned(
                      left: _focusIndicatorPosition!.dx - 26,
                      top: _focusIndicatorPosition!.dy - 26,
                      child: IgnorePointer(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFF4B66A),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = _reviewImagePath!;
    final quality = _reviewQuality;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: <Widget>[
              _TopIconButton(icon: Icons.arrow_back, onPressed: _retakePage),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Review capture',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (quality != null)
                _QualityChip(label: quality.label, clarity: quality.clarity),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ColoredBox(
                color: const Color(0xFF10151A),
                child: Center(
                  child: Image.file(File(imagePath), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF12181D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF27333C)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  Text(
                    quality?.message ?? 'Review the captured page.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _editReviewPage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF325059)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: const Icon(Icons.crop_rotate),
                      label: const Text('Edit Crop & Rotate'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _retakePage,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF325059)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _acceptPage(finish: false),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF265E56),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: const Text('Add Page'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _acceptPage(finish: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF4B66A),
                            foregroundColor: const Color(0xFF161B20),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            quality?.isBlurry == true ? 'Use Anyway' : 'Finish',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _flashIcon(FlashMode mode) {
    return switch (mode) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      _ => Icons.flash_off_rounded,
    };
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 24,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF151B20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF28343D)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF163036),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFFBFF0E2),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.clarity});

  final String label;
  final ScanClarity clarity;

  @override
  Widget build(BuildContext context) {
    final color = switch (clarity) {
      ScanClarity.blurry => const Color(0xFFD16A54),
      ScanClarity.fair => const Color(0xFFD6A24D),
      ScanClarity.sharp => const Color(0xFF2E8D70),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DocumentFrameOverlay extends StatelessWidget {
  const _DocumentFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xD9F4B66A), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Keep the document inside the frame',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFE7EEE9),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({
    required this.message,
    required this.onClose,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF12181D),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF28343D)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFFF4B66A),
                  size: 42,
                ),
                const SizedBox(height: 14),
                Text(
                  'Camera unavailable',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD6E1E0),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onClose,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF325059)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF4B66A),
                          foregroundColor: const Color(0xFF161B20),
                        ),
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
