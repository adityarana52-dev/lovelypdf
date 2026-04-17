import 'dart:io';

import 'package:image/image.dart' as img;

enum ScanClarity { blurry, fair, sharp }

class ScanQualityAssessment {
  const ScanQualityAssessment({required this.score, required this.clarity});

  final double score;
  final ScanClarity clarity;

  bool get isBlurry => clarity == ScanClarity.blurry;

  String get label => switch (clarity) {
    ScanClarity.blurry => 'Blurry',
    ScanClarity.fair => 'Fair',
    ScanClarity.sharp => 'Sharp',
  };

  String get message => switch (clarity) {
    ScanClarity.blurry =>
      'The text looks blurry. Retaking this page is recommended.',
    ScanClarity.fair =>
      'This page looks usable, but holding the phone more steadily may improve it.',
    ScanClarity.sharp => 'This page looks clear.',
  };
}

class ScanQualityService {
  const ScanQualityService();

  Future<ScanQualityAssessment> assessImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const ScanQualityAssessment(score: 50, clarity: ScanClarity.fair);
    }

    final resized = _prepare(decoded);
    final gray = img.grayscale(resized);
    final score = _laplacianScore(gray);

    final clarity = switch (score) {
      < 18 => ScanClarity.blurry,
      < 30 => ScanClarity.fair,
      _ => ScanClarity.sharp,
    };

    return ScanQualityAssessment(score: score, clarity: clarity);
  }

  img.Image _prepare(img.Image image) {
    const maxEdge = 320;
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= maxEdge) {
      return image;
    }

    if (image.width >= image.height) {
      return img.copyResize(
        image,
        width: maxEdge,
        interpolation: img.Interpolation.linear,
      );
    }

    return img.copyResize(
      image,
      height: maxEdge,
      interpolation: img.Interpolation.linear,
    );
  }

  double _laplacianScore(img.Image image) {
    if (image.width < 3 || image.height < 3) {
      return 0;
    }

    var total = 0.0;
    var samples = 0;

    for (var y = 1; y < image.height - 1; y += 2) {
      for (var x = 1; x < image.width - 1; x += 2) {
        final center = image.getPixel(x, y).r.toDouble();
        final left = image.getPixel(x - 1, y).r.toDouble();
        final right = image.getPixel(x + 1, y).r.toDouble();
        final top = image.getPixel(x, y - 1).r.toDouble();
        final bottom = image.getPixel(x, y + 1).r.toDouble();

        total += (4 * center - left - right - top - bottom).abs();
        samples += 1;
      }
    }

    if (samples == 0) {
      return 0;
    }

    final averageEdgeEnergy = total / samples;
    return (averageEdgeEnergy / 255.0) * 100;
  }
}
