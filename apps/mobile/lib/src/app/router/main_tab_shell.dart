import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/veil_ui.dart';

/// The shell of the three tab screens: the screen above the bottom bar with
/// Chats, Contacts and Settings. The bar is a plain [NavigationBar] on the
/// page colour with a hairline above it: no indicator, no ripple, the
/// active tab in the brand colour and the others muted.
class MainTabShell extends StatelessWidget {
  const MainTabShell({super.key, required this.child});

  final Widget child;

  static const _tabs = <_VeilNavTab>[
    _VeilNavTab(
      path: '/conversations',
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      label: _chatsLabel,
    ),
    _VeilNavTab(path: '/contacts', icon: Icons.people_outline, activeIcon: Icons.people, label: _contactsLabel),
    _VeilNavTab(
      path: '/settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: _settingsLabel,
    ),
  ];

  static String _chatsLabel(AppLocalizations l10n) => l10n.navChats;
  static String _contactsLabel(AppLocalizations l10n) => l10n.navContacts;
  static String _settingsLabel(AppLocalizations l10n) => l10n.navSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final currentPath = GoRouterState.of(context).fullPath ?? '/conversations';
    var currentIndex = _tabs.indexWhere((tab) => currentPath.startsWith(tab.path));
    if (currentIndex < 0) {
      currentIndex = 0;
    }

    return Scaffold(
      body: child,
      // The hairline is drawn over the bar, which is opaque and would
      // otherwise cover it.
      bottomNavigationBar: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.stroke, width: 0.5)),
        ),
        child: Theme(
          data: theme.copyWith(splashFactory: NoSplash.splashFactory),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              if (index != currentIndex) VeilHaptics.selection();
              context.go(_tabs[index].path);
            },
            destinations: [
              for (final tab in _tabs)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.activeIcon),
                  label: tab.label(l10n),
                  // The label is always shown; a tooltip would only say it
                  // again.
                  tooltip: '',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VeilNavTab {
  const _VeilNavTab({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final String path;
  final IconData icon;
  final IconData activeIcon;

  /// The tab's name in the user's language.
  final String Function(AppLocalizations l10n) label;
}
