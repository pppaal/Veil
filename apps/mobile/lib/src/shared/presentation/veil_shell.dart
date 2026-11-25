import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// The frame of a screen: an opaque 52dp bar with a hairline under it, the
/// page behind the content and the system insets.
///
/// The bar shows [title], or [titleWidget] in its place (a chat's name with
/// its marks, a search field), centred on iOS and at the start on Android.
/// [subtitle] goes under the title in small muted type; the Chats bar uses
/// it while the app is not connected. A screen that was pushed on top of
/// another gets a back button, unless [leading] takes its place.
///
/// A white page ([grouped] false: Chats, Contacts, the chat room, auth,
/// onboarding, the lock screen) draws on `canvas`; a grouped page
/// (Settings, Profile, Security, ...) draws on `canvasAlt`, and the groups
/// on it draw their containers. Lists are full-bleed, so [padding] is zero
/// unless a form screen asks for its 16.
class VeilShell extends StatelessWidget {
  const VeilShell({
    super.key,
    required this.child,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.actions,
    this.grouped = false,
    this.maxWidth = 840,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final String? title;

  /// Shown in the bar instead of [title].
  final Widget? titleWidget;

  /// One short line under [title]: "Connecting…", "Offline".
  final String? subtitle;

  /// Shown before the title instead of the back button.
  final Widget? leading;
  final List<Widget>? actions;

  /// Whether the page is a grouped page (see the class comment).
  final bool grouped;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  /// The height of the bar below the status bar.
  static const double barHeight = 52;

  /// The [padding] of a form screen (a field and its buttons, not a list):
  /// the 16 side gutter, 16 under the bar, 24 above the bottom.
  static const EdgeInsets formPadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

  /// Whether the nearest shell above [context] is a grouped page. A sheet,
  /// dialog or menu is not: it is one raised surface, so its rows run
  /// full-bleed on it as on a white page. Where there is neither (a bare
  /// page in a test) a group draws its container.
  static bool groupedOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_VeilPageScope>();
    if (scope != null) return scope.grouped;
    return ModalRoute.of(context) is! PopupRoute;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final page = grouped ? palette.canvasAlt : palette.canvas;
    final hasBar = title != null || titleWidget != null;
    final leading = this.leading ?? ((ModalRoute.of(context)?.canPop ?? false) ? const VeilBackButton() : null);
    final platform = theme.platform;
    final centred = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    Widget? middle = titleWidget;
    if (middle == null && title != null) {
      final titleText = Text(
        title!,
        style: theme.textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: centred ? TextAlign.center : TextAlign.start,
      );
      middle = subtitle == null
          ? titleText
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                titleText,
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
    }

    // The page colour is the scaffold's own: a coloured box between the
    // scaffold's Material and the rows would hide their ink.
    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: maxWidth == null
            ? Padding(padding: padding, child: child)
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: Padding(padding: padding, child: child),
              ),
      ),
    );

    return _VeilPageScope(
      grouped: grouped,
      child: Scaffold(
        backgroundColor: page,
        appBar: !hasBar
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(barHeight),
                child: Semantics(
                  container: true,
                  // A Material, so a control in the bar draws its ink on the
                  // bar and not under it.
                  child: Material(
                    color: page,
                    child: DecoratedBox(
                      // The hairline is drawn over the bar's last half point
                      // rather than under it, so the bar stays 52 and its
                      // content keeps the whole 52.
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: palette.stroke, width: 0.5)),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: barHeight,
                          // The bar has one fixed height: past this size its
                          // text would not fit it, so it stops growing there.
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.3,
                            child: NavigationToolbar(
                              centerMiddle: centred,
                              middleSpacing: leading == null ? VeilSpace.md : VeilSpace.xs,
                              leading: leading == null
                                  ? null
                                  : Padding(padding: const EdgeInsets.only(left: VeilSpace.xxs), child: leading),
                              middle: middle,
                              trailing: actions == null
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.only(right: VeilSpace.xxs),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        body: body,
      ),
    );
  }
}

class _VeilPageScope extends InheritedWidget {
  const _VeilPageScope({required this.grouped, required super.child});

  final bool grouped;

  @override
  bool updateShouldNotify(_VeilPageScope oldWidget) => oldWidget.grouped != grouped;
}

/// The back button of a [VeilShell] bar. It pops the screen, or runs
/// [onPressed] in its place (closing a search, leaving for a fixed screen).
/// The glyph is the platform's: the iOS chevron, the Android arrow.
class VeilBackButton extends StatelessWidget {
  const VeilBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      icon: cupertino ? const Icon(Icons.arrow_back_ios_new, size: 20) : const Icon(Icons.arrow_back, size: 24),
    );
  }
}
