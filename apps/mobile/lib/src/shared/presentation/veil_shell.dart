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
    // When a title is shown, the AppBar is translucent and content scrolls
    // under it — offset the content so the first child isn't obscured.
    final resolvedPadding = title == null
        ? padding
        : padding.add(const EdgeInsets.only(top: 52));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: title == null
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: VeilBlur(
                intensity: 22,
                tintAlpha: 0.62,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(
                      horizontal: VeilSpace.lg,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: palette.stroke.withValues(alpha: 0.45),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            style: VeilTypography.headline.copyWith(
                              color: palette.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (actions != null) ...[
                          const SizedBox(width: VeilSpace.sm),
                          ...actions!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.canvas,
              palette.canvasAlt,
              palette.surface,
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
                        padding: resolvedPadding,
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
