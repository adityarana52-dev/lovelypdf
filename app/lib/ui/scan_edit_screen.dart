import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ScanEditScreen extends StatefulWidget {
  const ScanEditScreen({super.key, required this.imagePath});

  static Future<String?> edit(BuildContext context, String imagePath) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ScanEditScreen(imagePath: imagePath),
        fullscreenDialog: true,
      ),
    );
  }

  final String imagePath;

  @override
  State<ScanEditScreen> createState() => _ScanEditScreenState();
}

class _ScanEditScreenState extends State<ScanEditScreen> {
  static const int _editorMaxEdge = 2200;
  static const double _handleRadius = 14;
  static const double _hitPadding = 26;
  static const List<num> _sharpenKernel = <num>[0, -1, 0, -1, 5, -1, 0, -1, 0];
  static const Rect _defaultCrop = Rect.fromLTWH(0.06, 0.06, 0.88, 0.88);

  img.Image? _workingImage;
  Uint8List? _previewBytes;
  Size? _imagePixelSize;
  Rect _normalizedCrop = _defaultCrop;
  _CropDragHandle? _activeHandle;
  Offset? _lastDragPosition;
  bool _isLoading = true;
  bool _isApplying = false;
  bool _isProcessingImage = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Could not decode the image.');
      }

      var baked = img.bakeOrientation(decoded);
      baked = _resizeForEditor(baked);

      if (!mounted) {
        return;
      }

      setState(() {
        _setWorkingImage(baked, resetCrop: true);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not open the editor for this page.';
      });
    }
  }

  img.Image _resizeForEditor(img.Image source) {
    final longestEdge = math.max(source.width, source.height);
    if (longestEdge <= _editorMaxEdge) {
      return source;
    }

    final scale = _editorMaxEdge / longestEdge;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  void _setWorkingImage(img.Image image, {required bool resetCrop}) {
    _workingImage = image;
    _imagePixelSize = Size(image.width.toDouble(), image.height.toDouble());
    _previewBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    if (resetCrop) {
      _normalizedCrop = _defaultCrop;
    }
  }

  Future<void> _rotate(double angle) async {
    final image = _workingImage;
    if (image == null || _isApplying || _isProcessingImage) {
      return;
    }

    setState(() {
      _isProcessingImage = true;
      _errorMessage = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final rotated = img.copyRotate(image, angle: angle);
      if (!mounted) {
        return;
      }
      setState(() {
        _setWorkingImage(rotated, resetCrop: true);
        _isProcessingImage = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessingImage = false;
        _errorMessage = 'Could not rotate this page.';
      });
    }
  }

  Future<void> _enhanceImage() async {
    final image = _workingImage;
    if (image == null || _isApplying || _isProcessingImage) {
      return;
    }

    setState(() {
      _isProcessingImage = true;
      _errorMessage = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final normalized = img.normalize(image.clone(), min: 0, max: 255);
      final adjusted = img.adjustColor(
        normalized,
        contrast: 1.06,
        brightness: 1.02,
        gamma: 0.98,
        saturation: 1.01,
      );
      final sharpened = img.convolution(
        adjusted,
        filter: _sharpenKernel,
        amount: 0.24,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _setWorkingImage(sharpened, resetCrop: false);
        _isProcessingImage = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessingImage = false;
        _errorMessage = 'Could not enhance this page.';
      });
    }
  }

  Future<void> _applyEdit() async {
    final image = _workingImage;
    if (image == null || _isApplying || _isProcessingImage) {
      return;
    }

    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    try {
      final left = (_normalizedCrop.left * image.width).round().clamp(
        0,
        image.width - 1,
      );
      final top = (_normalizedCrop.top * image.height).round().clamp(
        0,
        image.height - 1,
      );
      final right = (_normalizedCrop.right * image.width).round().clamp(
        left + 1,
        image.width,
      );
      final bottom = (_normalizedCrop.bottom * image.height).round().clamp(
        top + 1,
        image.height,
      );

      final cropped = img.copyCrop(
        image,
        x: left,
        y: top,
        width: math.max(1, right - left),
        height: math.max(1, bottom - top),
      );

      final editedPath = p.join(
        File(widget.imagePath).parent.path,
        '${p.basenameWithoutExtension(widget.imagePath)}_edit_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(
        editedPath,
      ).writeAsBytes(img.encodeJpg(cropped, quality: 97), flush: true);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop<String>(editedPath);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isApplying = false;
        _errorMessage = 'Could not apply your crop.';
      });
    }
  }

  Rect _imageDisplayRect(Size canvasSize) {
    final imageSize = _imagePixelSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return Rect.zero;
    }

    final imageAspect = imageSize.width / imageSize.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    late final double renderWidth;
    late final double renderHeight;

    if (imageAspect > canvasAspect) {
      renderWidth = canvasSize.width;
      renderHeight = renderWidth / imageAspect;
    } else {
      renderHeight = canvasSize.height;
      renderWidth = renderHeight * imageAspect;
    }

    return Rect.fromLTWH(
      (canvasSize.width - renderWidth) / 2,
      (canvasSize.height - renderHeight) / 2,
      renderWidth,
      renderHeight,
    );
  }

  Rect _cropRectFromImageRect(Rect imageRect) {
    return Rect.fromLTRB(
      imageRect.left + (_normalizedCrop.left * imageRect.width),
      imageRect.top + (_normalizedCrop.top * imageRect.height),
      imageRect.left + (_normalizedCrop.right * imageRect.width),
      imageRect.top + (_normalizedCrop.bottom * imageRect.height),
    );
  }

  void _resetCrop() {
    setState(() {
      _normalizedCrop = _defaultCrop;
      _activeHandle = null;
      _lastDragPosition = null;
    });
  }

  void _handleCropPanStart(DragStartDetails details, Rect imageRect) {
    final cropRect = _cropRectFromImageRect(imageRect);
    final handle = _resolveHandle(details.localPosition, cropRect, imageRect);
    if (handle == null) {
      return;
    }

    setState(() {
      _activeHandle = handle;
      _lastDragPosition = details.localPosition;
    });
  }

  void _handleCropPanUpdate(DragUpdateDetails details, Rect imageRect) {
    final handle = _activeHandle;
    final last = _lastDragPosition;
    if (handle == null || last == null) {
      return;
    }

    final delta = details.localPosition - last;
    final currentRect = _cropRectFromImageRect(imageRect);
    final nextRect = _updatedCropRect(
      handle: handle,
      cropRect: currentRect,
      imageRect: imageRect,
      delta: delta,
    );

    setState(() {
      _normalizedCrop = Rect.fromLTRB(
        ((nextRect.left - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
        ((nextRect.top - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
        ((nextRect.right - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
        ((nextRect.bottom - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
      );
      _lastDragPosition = details.localPosition;
    });
  }

  void _handleCropPanEnd(DragEndDetails details) {
    setState(() {
      _activeHandle = null;
      _lastDragPosition = null;
    });
  }

  _CropDragHandle? _resolveHandle(
    Offset position,
    Rect cropRect,
    Rect imageRect,
  ) {
    if (!imageRect.inflate(_hitPadding).contains(position)) {
      return null;
    }

    final nearLeft = (position.dx - cropRect.left).abs() <= _hitPadding;
    final nearRight = (position.dx - cropRect.right).abs() <= _hitPadding;
    final nearTop = (position.dy - cropRect.top).abs() <= _hitPadding;
    final nearBottom = (position.dy - cropRect.bottom).abs() <= _hitPadding;
    final withinVertical =
        position.dy >= cropRect.top - _hitPadding &&
        position.dy <= cropRect.bottom + _hitPadding;
    final withinHorizontal =
        position.dx >= cropRect.left - _hitPadding &&
        position.dx <= cropRect.right + _hitPadding;

    if (nearLeft && nearTop) {
      return _CropDragHandle.topLeft;
    }
    if (nearRight && nearTop) {
      return _CropDragHandle.topRight;
    }
    if (nearLeft && nearBottom) {
      return _CropDragHandle.bottomLeft;
    }
    if (nearRight && nearBottom) {
      return _CropDragHandle.bottomRight;
    }
    if (nearLeft && withinVertical) {
      return _CropDragHandle.left;
    }
    if (nearRight && withinVertical) {
      return _CropDragHandle.right;
    }
    if (nearTop && withinHorizontal) {
      return _CropDragHandle.top;
    }
    if (nearBottom && withinHorizontal) {
      return _CropDragHandle.bottom;
    }
    if (cropRect.contains(position)) {
      return _CropDragHandle.move;
    }
    return null;
  }

  Rect _updatedCropRect({
    required _CropDragHandle handle,
    required Rect cropRect,
    required Rect imageRect,
    required Offset delta,
  }) {
    final minWidth = math.min(
      imageRect.width - 8,
      math.max(72.0, imageRect.width * 0.14),
    );
    final minHeight = math.min(
      imageRect.height - 8,
      math.max(72.0, imageRect.height * 0.14),
    );

    var left = cropRect.left;
    var top = cropRect.top;
    var right = cropRect.right;
    var bottom = cropRect.bottom;

    if (handle == _CropDragHandle.move) {
      var dx = delta.dx;
      var dy = delta.dy;
      if (left + dx < imageRect.left) {
        dx = imageRect.left - left;
      }
      if (right + dx > imageRect.right) {
        dx = imageRect.right - right;
      }
      if (top + dy < imageRect.top) {
        dy = imageRect.top - top;
      }
      if (bottom + dy > imageRect.bottom) {
        dy = imageRect.bottom - bottom;
      }
      return cropRect.shift(Offset(dx, dy));
    }

    final adjustsLeft =
        handle == _CropDragHandle.left ||
        handle == _CropDragHandle.topLeft ||
        handle == _CropDragHandle.bottomLeft;
    final adjustsRight =
        handle == _CropDragHandle.right ||
        handle == _CropDragHandle.topRight ||
        handle == _CropDragHandle.bottomRight;
    final adjustsTop =
        handle == _CropDragHandle.top ||
        handle == _CropDragHandle.topLeft ||
        handle == _CropDragHandle.topRight;
    final adjustsBottom =
        handle == _CropDragHandle.bottom ||
        handle == _CropDragHandle.bottomLeft ||
        handle == _CropDragHandle.bottomRight;

    if (adjustsLeft) {
      left = (left + delta.dx).clamp(imageRect.left, right - minWidth);
    }
    if (adjustsRight) {
      right = (right + delta.dx).clamp(left + minWidth, imageRect.right);
    }
    if (adjustsTop) {
      top = (top + delta.dy).clamp(imageRect.top, bottom - minHeight);
    }
    if (adjustsBottom) {
      bottom = (bottom + delta.dy).clamp(top + minHeight, imageRect.bottom);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlsLocked = _isApplying || _isProcessingImage;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D10),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFF4B66A)),
              )
            : _errorMessage != null && _workingImage == null
            ? _EditorErrorState(
                message: _errorMessage!,
                onClose: () => Navigator.of(context).pop<String?>(null),
              )
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: controlsLocked
                              ? null
                              : () => Navigator.of(context).pop<String?>(null),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Crop & Rotate',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controlsLocked ? null : _applyEdit,
                          child: Text(
                            _isApplying ? 'Saving...' : 'Apply',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Text(
                      'Drag the crop border or corners, then apply the page.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD8E2E1),
                      ),
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFFFC9C0),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final imageRect = _imageDisplayRect(canvasSize);
                          final cropRect = _cropRectFromImageRect(imageRect);

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: controlsLocked
                                ? null
                                : (details) =>
                                      _handleCropPanStart(details, imageRect),
                            onPanUpdate: controlsLocked
                                ? null
                                : (details) =>
                                      _handleCropPanUpdate(details, imageRect),
                            onPanEnd: controlsLocked ? null : _handleCropPanEnd,
                            child: Stack(
                              children: <Widget>[
                                Positioned.fromRect(
                                  rect: imageRect,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10151A),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CropOverlayPainter(
                                        imageRect: imageRect,
                                        cropRect: cropRect,
                                        activeHandle: _activeHandle,
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
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final buttonWidth = (constraints.maxWidth - 12) / 2;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            SizedBox(
                              width: buttonWidth,
                              child: OutlinedButton.icon(
                                onPressed: controlsLocked
                                    ? null
                                    : _enhanceImage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF30414C),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                icon: _isProcessingImage
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.auto_fix_high),
                                label: Text(
                                  _isProcessingImage
                                      ? 'Processing...'
                                      : 'Enhance',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: buttonWidth,
                              child: FilledButton.icon(
                                onPressed: controlsLocked ? null : _resetCrop,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1F5E57),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                icon: const Icon(Icons.crop_free),
                                label: const Text('Reset Crop'),
                              ),
                            ),
                            SizedBox(
                              width: buttonWidth,
                              child: OutlinedButton.icon(
                                onPressed: controlsLocked
                                    ? null
                                    : () => _rotate(-90),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF30414C),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                icon: const Icon(Icons.rotate_left),
                                label: const Text('Rotate Left'),
                              ),
                            ),
                            SizedBox(
                              width: buttonWidth,
                              child: OutlinedButton.icon(
                                onPressed: controlsLocked
                                    ? null
                                    : () => _rotate(90),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF30414C),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                icon: const Icon(Icons.rotate_right),
                                label: const Text('Rotate Right'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _CropDragHandle {
  move,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.imageRect,
    required this.cropRect,
    required this.activeHandle,
  });

  final Rect imageRect;
  final Rect cropRect;
  final _CropDragHandle? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = const Color(0x8A000000);
    final clearPath = Path()
      ..addRect(imageRect)
      ..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(clearPath, overlayPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFF4B66A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = activeHandle == null ? 2.2 : 2.8;
    final cropRRect = RRect.fromRectAndRadius(
      cropRect,
      const Radius.circular(20),
    );
    canvas.drawRRect(cropRRect, borderPaint);

    final gridPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    final thirdWidth = cropRect.width / 3;
    final thirdHeight = cropRect.height / 3;
    for (var index = 1; index <= 2; index += 1) {
      final x = cropRect.left + (thirdWidth * index);
      final y = cropRect.top + (thirdHeight * index);
      canvas.drawLine(
        Offset(x, cropRect.top + 12),
        Offset(x, cropRect.bottom - 12),
        gridPaint,
      );
      canvas.drawLine(
        Offset(cropRect.left + 12, y),
        Offset(cropRect.right - 12, y),
        gridPaint,
      );
    }

    final handlePaint = Paint()..color = const Color(0xFFF4B66A);
    final handleStroke = Paint()
      ..color = const Color(0xFF0A0D10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in <Offset>[
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left, cropRect.center.dy),
      Offset(cropRect.right, cropRect.center.dy),
    ]) {
      canvas.drawCircle(
        point,
        _ScanEditScreenState._handleRadius / 2,
        handlePaint,
      );
      canvas.drawCircle(
        point,
        _ScanEditScreenState._handleRadius / 2,
        handleStroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.imageRect != imageRect ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.activeHandle != activeHandle;
  }
}

class _EditorErrorState extends StatelessWidget {
  const _EditorErrorState({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

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
                  Icons.crop_outlined,
                  color: Color(0xFFF4B66A),
                  size: 42,
                ),
                const SizedBox(height: 14),
                Text(
                  'Editor unavailable',
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
                FilledButton(
                  onPressed: onClose,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF4B66A),
                    foregroundColor: const Color(0xFF161B20),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
