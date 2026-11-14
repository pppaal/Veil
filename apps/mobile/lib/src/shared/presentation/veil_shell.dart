import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// The frame of a screen: the translucent top bar, the canvas behind the
/// content and the system insets.
///
/// The bar shows [title], or [titleWidget] in its place (a chat's name with
/// its marks, a search field). A screen that was pushed on top of another
/// gets a back button, unless [leading] takes its place.
class VeilShell extends StatelessWidget {
  const VeilShell({
    super.key,
    required this.child,
    this.title,
    this.titleWidget,
    this.leading,
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

  /// Shown in the bar instead of [title].
  final Widget? titleWidget;

  /// Shown before the title instead of the back button.
  final Widget? leading;
  final List<Widget>? actions;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final hasBar = title != null || titleWidget != null;
    final leading = this.leading ??
        ((ModalRoute.of(context)?.canPop ?? false) ? const VeilBackButton() : null);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: !hasBar
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
                    padding: EdgeInsets.only(
                      left: leading == null ? VeilSpace.lg : VeilSpace.xxs,
                      right: actions == null ? VeilSpace.lg : VeilSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: palette.stroke.withValues(alpha: 0.45),
                          width: 0.5,
                        ),
                      ),
                    ),
                    // The bar has one fixed height: past this size its text
                    // would not fit it, so it stops growing there.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Row(
                        children: [
                          if (leading != null) ...[
                            leading,
                            const SizedBox(width: VeilSpace.xxs),
                          ],
                          Expanded(
                            child: titleWidget ??
                                Text(
                                  title!,
                                  style: VeilTypography.headline.copyWith(
                                    color: palette.text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          ),
                          if (actions != null) ...[
                            const SizedBox(width: VeilSpace.xs),
                            ...actions!,
                          ],
                        ],
                      ),
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
                // The bar is translucent and the body runs behind it; the
                // SafeArea above already keeps the content clear of it, at
                // any width.
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

/// The back button of a [VeilShell] bar. It pops the screen, or runs
/// [onPressed] in its place (closing a search, leaving for a fixed screen).
class VeilBackButton extends StatelessWidget {
  const VeilBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      style: IconButton.styleFrom(backgroundColor: Colors.transparent),
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
    );
  }
}
