import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/veil_ui.dart';

/// The shell of the three tab screens: the screen above the bottom bar with
/// Chats, Contacts and Settings.
class MainTabShell extends StatelessWidget {
  const MainTabShell({super.key, required this.child});

  final Widget child;

  static const _tabs = <_VeilNavTab>[
    _VeilNavTab(path: '/conversations', icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: _chatsLabel),
    _VeilNavTab(path: '/contacts', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: _contactsLabel),
    _VeilNavTab(path: '/settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: _settingsLabel),
  ];

  static String _chatsLabel(AppLocalizations l10n) => l10n.navChats;
  static String _contactsLabel(AppLocalizations l10n) => l10n.navContacts;
  static String _settingsLabel(AppLocalizations l10n) => l10n.navSettings;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final currentPath = GoRouterState.of(context).fullPath ?? '/conversations';
    var currentIndex = _tabs.indexWhere((tab) => currentPath.startsWith(tab.path));
    if (currentIndex < 0) {
      currentIndex = 0;
    }

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: palette.stroke.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: VeilBlur(
          intensity: 28,
          tintAlpha: 0.72,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VeilSpace.md,
                vertical: VeilSpace.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final selected = index == currentIndex;
                  return Expanded(
                    child: VeilPressable(
                      haptic: false,
                      onTap: () {
                        if (!selected) {
                          VeilHaptics.selection();
                        }
                        context.go(tab.path);
                      },
                      scale: 0.92,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: VeilSpace.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: VeilMotion.fast,
                              curve: VeilMotion.springGentle,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(VeilRadius.pill),
                                color: selected ? palette.primarySoft : Colors.transparent,
                              ),
                              child: Icon(
                                selected ? tab.activeIcon : tab.icon,
                                size: 22,
                                color: selected ? palette.primary : palette.textSubtle,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tab.label(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                color: selected ? palette.primary : palette.textSubtle,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
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
