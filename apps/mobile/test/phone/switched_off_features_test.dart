import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/features/attachments/attachments_feature.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/profile/presentation/profile_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import 'phone_app.dart';

// This is a text-only build. The screens of what it could not do end to end
// (calls, a media picker, voice messages, a sticker picker, stories, an
// assistant, sending an attachment) are gone, and so are their routes, so
// nothing leads where there is no screen: no route, no tab, no button. One
// constant is left, kAttachmentsEnabled: the receive side of attachments is
// real, and it says what the chat does with one it was sent.

/// Where the deleted features lived. None of these may be a route again
/// before the feature works end to end.
const _deadPrefixes = ['/calls', '/call', '/media', '/voice', '/stickers', '/ai-chat', '/stories', '/story-viewer', '/attachment'];

Set<String> _paths(Iterable<RouteBase> routes) => {
      for (final route in routes) ...[
        if (route is GoRoute) route.path,
        ..._paths(route.routes),
      ],
    };

bool _under(String path, String prefix) => path == prefix || path.startsWith('$prefix/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;
  final AppLocalizations l10n = AppLocalizationsEn();

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('the route table has no route under the deleted features', (tester) async {
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    final app = _paths(world.container.read(appRoutesProvider));
    // Before the test ends: the messenger's timers go with it.
    world.dispose();

    for (final prefix in _deadPrefixes) {
      expect(app.where((path) => _under(path, prefix)), isEmpty, reason: 'a route under $prefix');
    }
    // What works has its route.
    expect(app, containsAll(['/conversations', '/contacts', '/settings', '/profile', '/secret-link']));
  });

  // A link into a feature that is gone (a `veil://` link, an unlock that
  // returns to `?from=`) must not end on the router's own "Page Not Found",
  // whose only button leads nowhere.
  testWidgets('a location no route has opens the conversation list, not a dead end', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    try {
      // The app's own router, guard and all.
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      expect(find.byType(ConversationListScreen), findsOneWidget);

      final nowhere = [
        '/calls',
        '/call/$chatConversationId',
        '/media/$chatConversationId',
        '/voice/$chatConversationId',
        '/stickers/$chatConversationId',
        '/ai-chat',
        '/stories',
        '/story-viewer/user-$peerHandle',
        '/attachment/$chatConversationId',
        '/no-such-screen',
        // Unlocked already, the lock passes on to where `from` points.
        '/lock?from=%2Fno-such-screen',
      ];
      for (final location in nowhere) {
        router.go('/contacts');
        await pumpFrames(tester, frames: 3);
        expect(find.byType(ContactsScreen), findsOneWidget);

        router.go(location);
        await pumpFrames(tester, frames: 3);
        expect(tester.takeException(), isNull, reason: location);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/conversations', reason: location);
        expect(find.byType(ConversationListScreen), findsOneWidget, reason: location);
        expect(find.textContaining('Not Found'), findsNothing, reason: location);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  testWidgets('the bottom bar is Chats, Contacts and Settings', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      for (final tab in [l10n.navChats, l10n.navContacts, l10n.navSettings]) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget,
            reason: 'the $tab tab');
      }

      // Settings is a tab: it opens with the bar still under it, and with
      // no back button, and the list's own bar has no second way there.
      expect(find.byIcon(Icons.tune), findsNothing);
      await tester.tap(find.text(l10n.navSettings));
      await pumpFrames(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(ConversationListScreen), findsNothing);
      expect(find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip), findsNothing);
      expect(find.text(l10n.navChats), findsOneWidget);

      await tester.tap(find.text(l10n.navContacts));
      await pumpFrames(tester);
      expect(find.byType(ContactsScreen), findsOneWidget);
    });
  });

  testWidgets('settings leads to the profile, where the nickname is edited', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await pumpFrames(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);

      // The nickname is a field of its own row; Save appears once it changes.
      await tester.enterText(find.byType(TextField), 'Moreau');
      await pumpFrames(tester, frames: 2);
      await tester.scrollUntilVisible(find.text(l10n.profileSaveNickname), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text(l10n.profileSaveNickname));
      await pumpFrames(tester, frames: 2);
      expect(world.container.read(appSessionProvider).displayName, 'Moreau');
    });
  });

  testWidgets('a chat offers an attachment only in a build that can send one', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/$chatConversationId', body: (world) async {
      expect(find.byTooltip(l10n.chatAttachAction), kAttachmentsEnabled ? findsOneWidget : findsNothing);

      // The seeded chat holds one message with an attachment. It is shown
      // for what it is; the download button only where a download works.
      await tester.dragUntilVisible(
        find.byType(MessageAttachmentCard),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await pumpFrames(tester, frames: 2);
      expect(find.byType(MessageAttachmentCard), findsOneWidget);
      expect(find.text(l10n.chatAttachmentResolveAction), kAttachmentsEnabled ? findsOneWidget : findsNothing);
      expect(find.text(l10n.chatAttachmentCannotOpen), kAttachmentsEnabled ? findsNothing : findsOneWidget);
    });
  });
}
