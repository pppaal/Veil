import 'package:flutter/material.dart';

/// The Veil mark: a "V" of two straight strokes of equal weight with round
/// caps, the stroke a ninth of the tile it would sit on, the V 52% of that
/// tile's width and a touch below its middle. It is the geometry
/// tool/brand.dart draws into the launcher icon and the native splash, so
/// the app's own splash continues the native one without a jump.
///
/// [width] is the width of the V. The splash and the app switcher's cover
/// show it alone on the page; it says nothing to a screen reader.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.width = 96});

  final double width;

  /// The colour of the native splash image, the same in both themes.
  static const Color color = Color(0xFF1F5FD6);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(width), painter: const _BrandMarkPainter(color)),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The tile the V is measured against, and the V's box inside it.
    final tile = size.width / 0.52;
    final radius = tile / 9 / 2;
    final height = tile * 0.50;
    final halfWidth = size.width / 2 - radius;
    final centre = size.center(Offset.zero);
    final drop = tile * 0.015;
    final top = centre.dy - height / 2 + radius + drop;
    final bottom = centre.dy + height / 2 - radius + drop;

    final path = Path()
      ..moveTo(centre.dx - halfWidth, top)
      ..lineTo(centre.dx, bottom)
      ..lineTo(centre.dx + halfWidth, top);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => oldDelegate.color != color;
}
