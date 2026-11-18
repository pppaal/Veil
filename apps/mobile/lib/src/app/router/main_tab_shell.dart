import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import '../../features/conversations/data/conversation_models.dart';
import '../../features/conversations/data/messenger_providers.dart';
import '../../features/safety/data/safety_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/veil_ui.dart';

/// The shell of the three tab screens: the screen above the bottom bar with
/// Chats, Contacts and Settings. The bar is a plain [NavigationBar] on the
/// page colour with a hairline above it: no indicator, no ripple, the
/// active tab in the brand colour and the others muted.
///
/// From [railBreakpoint] wide (a tablet, a desktop window) three tabs stretched
/// across the bottom would sit far apart: the same tabs are a
/// [NavigationRail] at the start edge instead, with a hairline beside it.
///
/// Chats carries a badge with the number of unread chats, as WhatsApp's
/// tab does: muted chats and blocked 1:1s left out, a chat marked unread
/// counted once, nothing at 0, "99+" past 99. Nothing on the app icon.
class MainTabShell extends ConsumerWidget {
  const MainTabShell({super.key, required this.child});

  final Widget child;

  /// The window width from which the tabs are a rail.
  static const double railBreakpoint = 1024;

  /// Whether a window [width] wide shows the tabs as a rail.
  static bool usesRail(double width) => width >= railBreakpoint;

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

  /// The badge on Chats; [count] 0 shows none.
  static Widget _chatsIcon(BuildContext context, IconData icon, int count) {
    final palette = context.veilPalette;
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: palette.primary,
      textColor: Colors.white,
      textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final mutes = ref.watch(conversationMutesProvider);
    final blocked = ref.watch(blockedAccountsProvider);
    final unreadChats = ref.watch(messengerControllerProvider.select((messenger) => messenger.reads.unreadChats(
          excluded: (id) {
            final conversation = messenger.conversationById(id);
            return mutes.isMuted(id) ||
                (conversation?.type == ConversationType.direct && blocked.isBlocked(conversation!.recipientBundle.userId));
          },
        )));
    // The tab says how many chats are unread; the badge's number is left
    // to that.
    Widget icon(_VeilNavTab tab, {required bool selected}) {
      final glyph = selected ? tab.activeIcon : tab.icon;
      if (tab.path != _tabs.first.path) return Icon(glyph);
      return Semantics(
        label: unreadChats > 0 ? l10n.navChatsUnreadSemantics(unreadChats) : null,
        child: ExcludeSemantics(child: _chatsIcon(context, glyph, unreadChats)),
      );
    }

    final currentPath = GoRouterState.of(context).fullPath ?? '/conversations';
    var currentIndex = _tabs.indexWhere((tab) => currentPath.startsWith(tab.path));
    if (currentIndex < 0) {
      currentIndex = 0;
    }
    void select(int index) {
      if (index != currentIndex) VeilHaptics.selection();
      context.go(_tabs[index].path);
    }

    if (usesRail(MediaQuery.sizeOf(context).width)) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final edge = BorderSide(color: palette.stroke, width: 0.5);
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The hairline is drawn over the rail's edge, as over the bar's.
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(border: rtl ? Border(left: edge) : Border(right: edge)),
              child: Theme(
                data: theme.copyWith(splashFactory: NoSplash.splashFactory),
                child: NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: select,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                        icon: icon(tab, selected: false),
                        selectedIcon: icon(tab, selected: true),
                        label: Text(tab.label(l10n)),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
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
            onDestinationSelected: select,
            destinations: [
              for (final tab in _tabs)
                NavigationDestination(
                  icon: icon(tab, selected: false),
                  selectedIcon: icon(tab, selected: true),
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
