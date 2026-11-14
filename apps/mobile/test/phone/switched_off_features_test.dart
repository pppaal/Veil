import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/features/ai/ai_feature.dart';
import 'package:veil_mobile/src/features/attachments/attachments_feature.dart';
import 'package:veil_mobile/src/features/calls/calls_feature.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/media/media_feature.dart';
import 'package:veil_mobile/src/features/profile/presentation/profile_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/features/stickers/stickers_feature.dart';
import 'package:veil_mobile/src/features/stories/stories_feature.dart';
import 'package:veil_mobile/src/features/voice/voice_feature.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../layout/support/screen_cases.dart';
import 'phone_app.dart';

// A feature this build cannot do end to end is switched off by its
// `k…Enabled` constant. While it is off nothing leads to it: no route, no
// tab, no button. Each check below reads the constant, so it keeps holding
// the day a feature is switched on (its routes are then the app's again).

/// The routes of each switchable feature, by its constant.
const _featureRoutes = <String, (bool enabled, List<String> paths)>{
  'calls': (kCallsEnabled, ['/calls', '/call/:conversationId']),
  'attachments': (kAttachmentsEnabled, ['/attachment/:conversationId']),
  'media picker': (kMediaPickerEnabled, ['/media/:conversationId']),
  'voice messages': (kVoiceMessagesEnabled, ['/voice/:conversationId']),
  'sticker picker': (kStickerPickerEnabled, ['/stickers/:conversationId']),
  'assistant': (kAssistantEnabled, ['/ai-chat']),
  'stories': (kStoriesEnabled, ['/stories', '/story-viewer/:userId']),
};

Set<String> _paths(Iterable<RouteBase> routes) => {
      for (final route in routes) ...[
        if (route is GoRoute) route.path,
        ..._paths(route.routes),
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;
  final AppLocalizations l10n = AppLocalizationsEn();

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('the route table has a feature\'s routes only while the feature is on', (tester) async {
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    final app = _paths(world.container.read(appRoutesProvider));
    // Before the test ends: the messenger's timers go with it.
    world.dispose();
    final testOnly = _paths(layoutOnlyRoutes);

    for (final MapEntry(key: feature, value: (enabled, paths)) in _featureRoutes.entries) {
      for (final path in paths) {
        expect(app.contains(path), enabled, reason: '$feature is ${enabled ? 'on' : 'off'}: $path');
        // What the app leaves out, the layout gate still reaches.
        expect(testOnly.contains(path), !enabled, reason: '$feature: $path in layoutOnlyRoutes');
      }
    }
    // What works has its route whatever is switched off.
    expect(app, containsAll(['/conversations', '/contacts', '/settings', '/profile', '/secret-link']));
  });

  // A link into a feature that is off (a `veil://` link, an unlock that
  // returns to `?from=`) must not end on the router's own "Page Not Found",
  // whose only button leads nowhere.
  testWidgets('a location no route has opens the conversation list, not a dead end', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'ko');
    try {
      // The app's own router, guard and all.
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      expect(find.byType(ConversationListScreen), findsOneWidget);

      final nowhere = [
        for (final (enabled, paths) in _featureRoutes.values)
          if (!enabled)
            for (final path in paths)
              path.replaceFirst(':conversationId', chatConversationId).replaceFirst(':userId', 'user-$peerHandle'),
        '/no-such-screen',
        // Unlocked already, the lock passes on to where `from` points.
        '/lock?from=%2Fno-such-screen',
      ];
      expect(nowhere, hasLength(greaterThan(2)));
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

  testWidgets('the bottom bar is Chats, Contacts and Settings, plus the tabs of features that are on',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      for (final tab in [l10n.navChats, l10n.navContacts, l10n.navSettings]) {
        expect(find.text(tab), findsOneWidget, reason: 'the $tab tab');
      }
      expect(find.text(l10n.navCalls), kCallsEnabled ? findsOneWidget : findsNothing);
      expect(find.text(l10n.navStories), kStoriesEnabled ? findsOneWidget : findsNothing);

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
      await tester.tap(find.text(l10n.settingsProfileTitle));
      await pumpFrames(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.scrollUntilVisible(find.text(l10n.profileEditNickname), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text(l10n.profileEditNickname));
      await pumpFrames(tester, frames: 2);
      await tester.enterText(find.byType(TextField), 'Moreau');
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
