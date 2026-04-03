import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

class VeilShell extends StatelessWidget {
  const VeilShell({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.maxWidth = 840,
    this.padding = const EdgeInsets.fromLTRB(
      VeilSpace.lg,
      VeilSpace.lg,
      VeilSpace.lg,
      VeilSpace.xl,
    ),
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.canvas,
              palette.canvasAlt,
              const Color(0xFF10161D),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: -140,
                right: -90,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withValues(alpha: 0.06),
                          blurRadius: 90,
                          spreadRadius: 18,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 300, height: 300),
                  ),
                ),
              ),
              Positioned(
                top: 120,
                left: -140,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withValues(alpha: 0.03),
                          blurRadius: 120,
                          spreadRadius: 30,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 360, height: 360),
                  ),
                ),
              ),
              Positioned(
                bottom: -160,
                left: -120,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.surfaceRaised.withValues(alpha: 0.38),
                          blurRadius: 100,
                          spreadRadius: 24,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 320, height: 320),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: maxWidth == null
                    ? Padding(
                        padding: padding,
                        child: child,
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth!),
                        child: Padding(
                          padding: padding,
                          child: child,
                        ),
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
