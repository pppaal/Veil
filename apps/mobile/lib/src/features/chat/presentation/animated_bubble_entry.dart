import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';

/// Fades and slides a message in from its own side as it first appears.
class AnimatedBubbleEntry extends StatefulWidget {
  const AnimatedBubbleEntry({super.key, required this.child, this.fromRight = false});

  final Widget child;
  final bool fromRight;

  @override
  State<AnimatedBubbleEntry> createState() => _AnimatedBubbleEntryState();
}

class _AnimatedBubbleEntryState extends State<AnimatedBubbleEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: VeilMotion.normal,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    final dx = widget.fromRight ? 0.08 : -0.08;
    _slide = Tween<Offset>(
      begin: Offset(dx, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: VeilMotion.emphasize,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
