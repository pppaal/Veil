import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';

/// Signal's read glyph, as the web draws it (`i-tick-read`): two filled
/// circles, the front one whole and the one behind cut back to a crescent
/// by a thin ring, each with its check cut out in [cutColor], the bubble's
/// fill. Two filled glyphs stacked plainly would merge into one pill whose
/// second disc covers the first check.
///
/// It takes the box the two outlined circles of "delivered" take, so the
/// time does not move when a message is read, and circles the size of the
/// one outlined circle of "sent".
class MessageReadGlyph extends StatelessWidget {
  const MessageReadGlyph({super.key, required this.color, required this.cutColor});

  /// The circles' colour (the bubble's meta colour).
  final Color color;

  /// The colour the checks are cut out in: the bubble's fill.
  final Color cutColor;

  /// The box it is drawn in: the delivered glyph's.
  static const Size size = Size(VeilIconSize.xs + 6, VeilIconSize.xs);

  /// Where it is drawn in a box of [size]: the circles' centres and radius,
  /// the ring that cuts the back circle, and each check as three points.
  @visibleForTesting
  static ReadGlyphGeometry geometry(Size size) {
    // In units of the web symbol (32 by 24): circles of radius 8, the back
    // one cut by a ring of 9.5 around the front one, set 10.5 apart so the
    // back check fits whole inside the crescent. Scaled so the circles
    // match a Material check circle's (radius 10 of 24).
    final radius = size.height * 10 / 24;
    final unit = radius / 8;
    final spread = 10.5 * unit;
    final left = (size.width - (2 * radius + spread)) / 2;
    final front = Offset(left + radius, size.height / 2);
    final back = front.translate(spread, 0);
    List<Offset> check(Offset centre, List<(double, double)> points) =>
        [for (final (x, y) in points) centre.translate(x * unit, y * unit)];
    return ReadGlyphGeometry(
      front: front,
      back: back,
      radius: radius,
      ring: 9.5 * unit,
      stroke: 1.75 * unit,
      frontCheck: check(front, const [(-3.4, 0.2), (-1.1, 2.5), (3.3, -2.1)]),
      // The same check at three quarters, centred in the crescent.
      backCheck: check(back, const [(1.09, 0.15), (2.81, 1.88), (6.12, -1.58)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: size, painter: _ReadGlyphPainter(color: color, cutColor: cutColor));
  }
}

/// Where [MessageReadGlyph] draws its parts.
@visibleForTesting
class ReadGlyphGeometry {
  const ReadGlyphGeometry({
    required this.front,
    required this.back,
    required this.radius,
    required this.ring,
    required this.stroke,
    required this.frontCheck,
    required this.backCheck,
  });

  final Offset front;
  final Offset back;
  final double radius;

  /// The radius around [front] that the back circle is cut away inside.
  final double ring;

  /// The checks' stroke width.
  final double stroke;
  final List<Offset> frontCheck;
  final List<Offset> backCheck;
}

class _ReadGlyphPainter extends CustomPainter {
  const _ReadGlyphPainter({required this.color, required this.cutColor});

  final Color color;
  final Color cutColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = MessageReadGlyph.geometry(size);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: g.back, radius: g.radius)),
      Path()..addOval(Rect.fromCircle(center: g.front, radius: g.ring)),
    );
    canvas
      ..drawPath(crescent, fill)
      ..drawCircle(g.front, g.radius, fill);
    final cut = Paint()
      ..color = cutColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final points in [g.frontCheck, g.backCheck]) {
      canvas.drawPath(Path()..addPolygon(points, false), cut);
    }
  }

  @override
  bool shouldRepaint(_ReadGlyphPainter old) => old.color != color || old.cutColor != cutColor;
}
