import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final outDir = Directory('assets/branding');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  _writePng('${outDir.path}/app_icon.png', _buildAppIcon(1024, rounded: false));
  _writePng(
    '${outDir.path}/app_icon_rounded.png',
    _buildAppIcon(1024, rounded: true),
  );
  _writePng(
    '${outDir.path}/app_icon_foreground.png',
    _buildForegroundMark(1024),
  );
  _writePng('${outDir.path}/splash.png', _buildSplashMark(512));
  _writePng('${outDir.path}/splash_branding.png', _buildWordmark(1200, 180));

  stdout.writeln('Brand assets generated in ${outDir.path}');
}

void _writePng(String path, img.Image image) {
  final png = img.encodePng(image, level: 9);
  File(path).writeAsBytesSync(png);
}

img.Image _buildAppIcon(int size, {required bool rounded}) {
  final image = img.Image(width: size, height: size);
  _paintRadialBackground(image);
  _paintGlowRing(image, strokeWidth: size * 0.012);
  _paintVMark(image, strokeWidth: size * 0.12);
  if (rounded) {
    return _roundCorners(image, (size * 0.22).round());
  }
  return image;
}

img.Image _buildForegroundMark(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  _paintVMark(image, strokeWidth: size * 0.14);
  return image;
}

img.Image _buildSplashMark(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  _paintVMark(image, strokeWidth: size * 0.11);
  return image;
}

img.Image _buildWordmark(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  final baseline = height * 0.72;
  final letterHeight = height * 0.58;
  final letterWidth = letterHeight * 0.78;
  final spacing = letterWidth * 0.38;
  final totalWidth = letterWidth * 4 + spacing * 3;
  final startX = (width - totalWidth) / 2;

  const letters = ['V', 'E', 'I', 'L'];
  for (var i = 0; i < letters.length; i++) {
    final x = startX + i * (letterWidth + spacing);
    _drawCapitalLetter(
      image,
      letter: letters[i],
      x: x,
      baseline: baseline,
      letterWidth: letterWidth,
      letterHeight: letterHeight,
      stroke: (height * 0.085).round(),
    );
  }

  return image;
}

void _paintRadialBackground(img.Image image) {
  final cx = image.width / 2;
  final cy = image.height / 2;
  final maxR = math.sqrt(cx * cx + cy * cy);
  final inner = _hex('0F1626');
  final outer = _hex('05070D');

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final r = math.sqrt(dx * dx + dy * dy) / maxR;
      final t = math.pow(r, 1.25).toDouble().clamp(0.0, 1.0);
      final color = _lerp(inner, outer, t);
      image.setPixelRgba(x, y, color.r, color.g, color.b, 255);
    }
  }
}

void _paintGlowRing(img.Image image, {required double strokeWidth}) {
  final cx = image.width / 2;
  final cy = image.height / 2;
  final radius = image.width * 0.44;
  final ringColor = _hex('6C8CFF');

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distance = math.sqrt(dx * dx + dy * dy);
      final edgeDistance = (distance - radius).abs();
      if (edgeDistance <= strokeWidth) {
        final falloff = math.pow(1 - edgeDistance / strokeWidth, 2).toDouble();
        final alpha = (falloff * 140).round().clamp(0, 255);
        _blendPixel(image, x, y, ringColor, alpha);
      } else if (edgeDistance <= strokeWidth * 6) {
        final falloff =
            math.pow(1 - (edgeDistance - strokeWidth) / (strokeWidth * 5), 3)
                .toDouble();
        final alpha = (falloff * 55).round().clamp(0, 255);
        if (alpha > 0) {
          _blendPixel(image, x, y, ringColor, alpha);
        }
      }
    }
  }
}

void _paintVMark(img.Image image, {required double strokeWidth}) {
  final cx = image.width / 2;
  final cy = image.height / 2;
  final height = image.height * 0.44;
  final width = image.width * 0.42;

  final topLeft = _Point(cx - width / 2, cy - height / 2);
  final topRight = _Point(cx + width / 2, cy - height / 2);
  final bottom = _Point(cx, cy + height / 2);

  final leftGrad = _GradientStop(start: _hex('9BB1FF'), end: _hex('6C8CFF'));
  final rightGrad = _GradientStop(start: _hex('6C8CFF'), end: _hex('8B5CF6'));

  _strokeLine(image, topLeft, bottom, strokeWidth, leftGrad);
  _strokeLine(image, topRight, bottom, strokeWidth, rightGrad);
  _fillCircle(image, bottom, strokeWidth / 2, rightGrad.end);
  _fillCircle(image, topLeft, strokeWidth / 2, leftGrad.start);
  _fillCircle(image, topRight, strokeWidth / 2, rightGrad.start);
}

void _drawCapitalLetter(
  img.Image image, {
  required String letter,
  required double x,
  required double baseline,
  required double letterWidth,
  required double letterHeight,
  required int stroke,
}) {
  final top = baseline - letterHeight;
  final mid = baseline - letterHeight / 2;
  final right = x + letterWidth;
  final color = _hex('F0F4FA');

  switch (letter) {
    case 'V':
      _strokeLine(
        image,
        _Point(x, top),
        _Point(x + letterWidth / 2, baseline),
        stroke.toDouble(),
        _GradientStop(start: color, end: color),
      );
      _strokeLine(
        image,
        _Point(right, top),
        _Point(x + letterWidth / 2, baseline),
        stroke.toDouble(),
        _GradientStop(start: color, end: color),
      );
      break;
    case 'E':
      _strokeLine(image, _Point(x, top), _Point(x, baseline), stroke.toDouble(),
          _GradientStop(start: color, end: color));
      _strokeLine(image, _Point(x, top), _Point(right, top), stroke.toDouble(),
          _GradientStop(start: color, end: color));
      _strokeLine(image, _Point(x, mid), _Point(x + letterWidth * 0.8, mid),
          stroke.toDouble(), _GradientStop(start: color, end: color));
      _strokeLine(image, _Point(x, baseline), _Point(right, baseline),
          stroke.toDouble(), _GradientStop(start: color, end: color));
      break;
    case 'I':
      final centerX = x + letterWidth / 2;
      _strokeLine(image, _Point(centerX, top), _Point(centerX, baseline),
          stroke.toDouble(), _GradientStop(start: color, end: color));
      break;
    case 'L':
      _strokeLine(image, _Point(x, top), _Point(x, baseline), stroke.toDouble(),
          _GradientStop(start: color, end: color));
      _strokeLine(image, _Point(x, baseline), _Point(right, baseline),
          stroke.toDouble(), _GradientStop(start: color, end: color));
      break;
  }
}

void _strokeLine(
  img.Image image,
  _Point a,
  _Point b,
  double width,
  _GradientStop gradient,
) {
  final minX = (math.min(a.x, b.x) - width).floor().clamp(0, image.width - 1);
  final maxX = (math.max(a.x, b.x) + width).ceil().clamp(0, image.width - 1);
  final minY = (math.min(a.y, b.y) - width).floor().clamp(0, image.height - 1);
  final maxY = (math.max(a.y, b.y) + width).ceil().clamp(0, image.height - 1);

  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) return;
  final half = width / 2;

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final t = ((x - a.x) * dx + (y - a.y) * dy) / lengthSq;
      if (t < 0 || t > 1) continue;
      final px = a.x + t * dx;
      final py = a.y + t * dy;
      final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      if (d <= half) {
        final soft = (half - d).clamp(0.0, 1.2);
        final alpha = (soft * 220).clamp(0, 255).round();
        final color = _lerp(gradient.start, gradient.end, t);
        _blendPixel(image, x, y, color, alpha);
      }
    }
  }
}

void _fillCircle(img.Image image, _Point center, double radius, _Rgb color) {
  final minX = (center.x - radius).floor().clamp(0, image.width - 1);
  final maxX = (center.x + radius).ceil().clamp(0, image.width - 1);
  final minY = (center.y - radius).floor().clamp(0, image.height - 1);
  final maxY = (center.y + radius).ceil().clamp(0, image.height - 1);
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - center.x;
      final dy = y - center.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= radius) {
        final alpha =
            ((radius - d).clamp(0.0, 1.5) * 200).clamp(0, 255).round();
        _blendPixel(image, x, y, color, alpha);
      }
    }
  }
}

img.Image _roundCorners(img.Image image, int radius) {
  final result = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 4,
  );
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final inCorner = _cornerDistance(x, y, image.width, image.height, radius);
      final source = image.getPixel(x, y);
      if (inCorner >= 0) {
        final a = (1.0 - inCorner.clamp(0.0, 1.0)) * 255;
        result.setPixelRgba(
          x,
          y,
          source.r.toInt(),
          source.g.toInt(),
          source.b.toInt(),
          a.round(),
        );
      } else {
        result.setPixelRgba(
          x,
          y,
          source.r.toInt(),
          source.g.toInt(),
          source.b.toInt(),
          255,
        );
      }
    }
  }
  return result;
}

double _cornerDistance(int x, int y, int w, int h, int radius) {
  double? cornerX;
  double? cornerY;
  if (x < radius && y < radius) {
    cornerX = radius.toDouble();
    cornerY = radius.toDouble();
  } else if (x >= w - radius && y < radius) {
    cornerX = (w - radius).toDouble();
    cornerY = radius.toDouble();
  } else if (x < radius && y >= h - radius) {
    cornerX = radius.toDouble();
    cornerY = (h - radius).toDouble();
  } else if (x >= w - radius && y >= h - radius) {
    cornerX = (w - radius).toDouble();
    cornerY = (h - radius).toDouble();
  }
  if (cornerX == null || cornerY == null) return -1;
  final dx = x - cornerX;
  final dy = y - cornerY;
  final d = math.sqrt(dx * dx + dy * dy);
  return (d - radius).clamp(-1.0, 1.0);
}

void _blendPixel(img.Image image, int x, int y, _Rgb color, int alpha) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
  final src = image.getPixel(x, y);
  final srcA = src.a.toInt();
  final blendA = alpha.clamp(0, 255);
  final outA = srcA + ((255 - srcA) * blendA ~/ 255);
  final srcR = src.r.toInt();
  final srcG = src.g.toInt();
  final srcB = src.b.toInt();
  final outR = (color.r * blendA + srcR * (255 - blendA)) ~/ 255;
  final outG = (color.g * blendA + srcG * (255 - blendA)) ~/ 255;
  final outB = (color.b * blendA + srcB * (255 - blendA)) ~/ 255;
  image.setPixelRgba(x, y, outR, outG, outB, outA);
}

_Rgb _lerp(_Rgb a, _Rgb b, double t) {
  final cl = t.clamp(0.0, 1.0);
  return _Rgb(
    (a.r + (b.r - a.r) * cl).round(),
    (a.g + (b.g - a.g) * cl).round(),
    (a.b + (b.b - a.b) * cl).round(),
  );
}

_Rgb _hex(String hex) {
  final value = int.parse(hex, radix: 16);
  return _Rgb((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

class _GradientStop {
  const _GradientStop({required this.start, required this.end});
  final _Rgb start;
  final _Rgb end;
}
