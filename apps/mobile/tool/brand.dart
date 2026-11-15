import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Draws the brand assets (docs/mobile-design-system.md, section 13) into
// assets/branding. Run from apps/mobile:
//
//   dart run tool/brand.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// The mark is a "V" of two straight strokes of equal weight with round
// caps: the stroke is a ninth of the tile, the V spans 52% of the tile's
// width and sits optically centred (a touch below the middle, since a V
// carries its weight at the top). No gradient, no second colour, no
// wordmark. Each PNG has exactly two colours (or one colour and
// transparency): the edges are not antialiased here, since the platform
// generators resample these sources to every icon size anyway.

const _blue = (0x1F, 0x5F, 0xD6);
const _white = (0xFF, 0xFF, 0xFF);

void main() {
  final outDir = Directory('assets/branding');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // iOS and the plain Android icon: the mark on the blue tile.
  _write('${outDir.path}/app_icon.png', _tile(1024, background: _blue, mark: _white, markTile: 1024));
  // The Android adaptive foreground: the mark alone, sized for the 72 of
  // the 108dp canvas that the launcher shows.
  _write(
    '${outDir.path}/app_icon_foreground.png',
    _tile(1024, background: null, mark: _white, markTile: 1024 * 72 / 108),
  );
  // The splash image, read by flutter_native_splash as a 4x asset: a 128dp
  // canvas with the V 96dp wide, in blue on transparent.
  _write('${outDir.path}/splash.png', _tile(512, background: null, mark: _blue, markTile: 96 * 4 / 0.52));

  stdout.writeln('Brand assets written to ${outDir.path}');
}

void _write(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image, level: 9));
}

/// A [size] square: [background] (or transparent) with the mark drawn as
/// it would be on a tile [markTile] wide, centred.
img.Image _tile(int size, {required (int, int, int)? background, required (int, int, int) mark, required double markTile}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final (br, bg, bb) = background ?? (0, 0, 0);
  final backgroundAlpha = background == null ? 0 : 255;
  final (mr, mg, mb) = mark;

  final geometry = _MarkGeometry(tile: markTile, centre: size / 2);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (geometry.covers(x + 0.5, y + 0.5)) {
        image.setPixelRgba(x, y, mr, mg, mb, 255);
      } else {
        image.setPixelRgba(x, y, br, bg, bb, backgroundAlpha);
      }
    }
  }
  return image;
}

/// The two strokes of the V, as capsules, and whether a pixel is inside.
class _MarkGeometry {
  _MarkGeometry({required double tile, required double centre}) : radius = tile / 9 / 2 {
    final span = tile * 0.52;
    final height = tile * 0.50;
    // The strokes' centre lines stay a radius inside the glyph's outer box.
    final halfWidth = span / 2 - radius;
    final top = centre - height / 2 + radius + tile * 0.015;
    final bottom = centre + height / 2 - radius + tile * 0.015;
    left = (centre - halfWidth, top);
    right = (centre + halfWidth, top);
    point = (centre, bottom);
  }

  final double radius;
  late final (double, double) left;
  late final (double, double) right;
  late final (double, double) point;

  /// Whether the pixel centre (x, y) is inside one of the two strokes.
  bool covers(double x, double y) =>
      math.min(_distanceToSegment(x, y, left, point), _distanceToSegment(x, y, right, point)) <= radius;

  static double _distanceToSegment(double x, double y, (double, double) a, (double, double) b) {
    final (ax, ay) = a;
    final (bx, by) = b;
    final dx = bx - ax, dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    return math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
  }
}
