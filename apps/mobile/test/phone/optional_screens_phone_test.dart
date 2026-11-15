import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/ai/presentation/ai_chat_screen.dart';
import 'package:veil_mobile/src/features/attachments/presentation/attachment_preview_screen.dart';
import 'package:veil_mobile/src/features/calls/data/call_history_providers.dart';
import 'package:veil_mobile/src/features/calls/presentation/call_history_screen.dart';
import 'package:veil_mobile/src/features/calls/presentation/call_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/media/presentation/media_picker_screen.dart';
import 'package:veil_mobile/src/features/stickers/data/emoji_catalog.dart';
import 'package:veil_mobile/src/features/stickers/presentation/sticker_picker_screen.dart';
import 'package:veil_mobile/src/features/stories/data/story_feed_providers.dart';
import 'package:veil_mobile/src/features/stories/presentation/stories_screen.dart';
import 'package:veil_mobile/src/features/stories/presentation/story_viewer_screen.dart';
import 'package:veil_mobile/src/features/voice/presentation/voice_recorder_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/screen_cases.dart' show layoutOnlyRoutes;
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The screens of the features this build has switched off (calls, the media
// picker, voice messages, the emoji picker, stories, the assistant,
// attachments). Each shows only what the build can do: a screen for
// something it cannot do says so and plays nothing, a list shows what the
// relay really holds, and what can be tapped does what it says.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // One of the screens above, alone, in the dark theme.
  Widget alone(Widget screen, {List<Override> overrides = const [], String locale = 'en'}) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: VeilTheme.dark(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      );

  // Opens [location] on top of the conversation list, the way a button in
  // the app would, and returns what the route gives back when it closes.
  Object? Function() pushOver(WidgetTester tester, String location, {Object? extra}) {
    Object? result;
    var closed = false;
    GoRouter.of(tester.element(find.byType(ConversationListScreen))).push<Object?>(location, extra: extra).then((value) {
      result = value;
      closed = true;
    });
    return () {
      expect(closed, isTrue, reason: '$location is still open');
      return result;
    };
  }

  group('call screen', () {
    testWidgets('says no call can be made, and never plays one', (tester) async {
      await withPhoneApp(tester, identities,
          location: '/call/$chatConversationId',
          prepare: (_) async => {'name': 'Selene Park'},
          extraRoutes: layoutOnlyRoutes,
          body: (world) async {
        expect(find.text('Selene Park'), findsOneWidget);
        expect(findCopy(en.callScreenUnavailableTitle), findsOneWidget);
        expect(findCopy(en.callScreenUnavailableBody), findsOneWidget);

        // However long it stays open, no call starts: no status of one, no
        // running time, none of a call's controls.
        for (var second = 0; second < 12; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(findCopy(en.callScreenUnavailableTitle), findsOneWidget);
        expect(find.textContaining(RegExp(r'\d:\d\d')), findsNothing, reason: 'a call timer');
        for (final control in [
          Icons.mic_none_rounded,
          Icons.mic_off_rounded,
          Icons.volume_up_rounded,
          Icons.volume_down_rounded,
          Icons.videocam_rounded,
          Icons.videocam_off_rounded,
          Icons.call_end_rounded,
        ]) {
          expect(find.byIcon(control), findsNothing, reason: 'a control of a call that does not exist');
        }
        expect(find.byType(OutlinedButton), findsOneWidget, reason: 'the one thing to do is leave');
        expect(find.byType(FilledButton), findsNothing);

        // Opened as the first screen, there is nothing under it to go back
        // to: Close leads to the conversation list.
        await tester.tap(find.text(en.commonClose));
        await pumpFrames(tester);
        expect(find.byType(CallScreen), findsNothing);
        expect(find.byType(ConversationListScreen), findsOneWidget);
      });
    });

    testWidgets('closes back to the screen it was opened from', (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', extraRoutes: layoutOnlyRoutes,
          body: (world) async {
        pushOver(tester, '/call/$chatConversationId', extra: {'name': 'Selene Park'});
        await pumpFrames(tester);
        expect(find.byType(CallScreen), findsOneWidget);
        expect(find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip), findsOneWidget);

        await tester.tap(find.text(en.commonClose));
        await pumpFrames(tester);
        expect(find.byType(CallScreen), findsNothing);
        expect(find.byType(ConversationListScreen), findsOneWidget);
      });
    });

    testWidgets('without a name it still says what it cannot do', (tester) async {
      await tester.pumpWidget(alone(const CallScreen(contactName: '')));
      await tester.pump();
      expect(findCopy(en.callScreenUnavailableTitle), findsOneWidget);
      expect(find.byIcon(Icons.phone_disabled_rounded), findsOneWidget);
    });
  });

  group('call history', () {
    testWidgets('a row opens the chat with that person, and says calls cannot be placed', (tester) async {
      await withPhoneApp(tester, identities, location: '/calls', extraRoutes: layoutOnlyRoutes, body: (world) async {
        expect(findCopy(en.callsNotice), findsOneWidget);
        expect(find.text('Selene Park'), findsOneWidget);

        await tester.tap(find.text('한지우'));
        await pumpFrames(tester);
        expect(find.byType(SnackBar), findsNothing, reason: 'a row does something, it does not excuse itself');
        expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, 'conv-jiwoo');
      });
    });

    testWidgets('names a person as their chat does, and nobody as "Unknown" in Korean', (tester) async {
      Map<String, dynamic> record(String id, {String? counterparty, String? handle}) => {
            'id': id,
            'conversationId': 'conv-$id',
            'counterparty': counterparty,
            'counterpartyHandle': handle,
            'callType': 'voice',
            'status': 'ended',
            'initiatedByMe': true,
            'duration': 5,
            'startedAt': DateTime.now().toUtc().toIso8601String(),
          };
      await withPhoneApp(tester, identities,
          location: '/calls',
          locale: 'ko',
          extraRoutes: layoutOnlyRoutes,
          // What the relay sends: a handle for a person, a name for a group,
          // and the word "Unknown" when it has neither.
          prepare: (world) async {
            world.api.callRecords = [
              record(peerHandle, counterparty: peerHandle, handle: peerHandle),
              record('stranger', counterparty: 'stranger', handle: 'stranger'),
              record('group', counterparty: 'Hiking club'),
              record('gone', counterparty: 'Unknown'),
            ];
            return null;
          },
          body: (world) async {
        expect(find.text('Selene Park'), findsOneWidget, reason: 'the name the chat with @selene shows');
        expect(find.text('@stranger'), findsOneWidget, reason: 'nobody this device chats with: the handle');
        expect(find.text('Hiking club'), findsOneWidget);
        expect(find.text(ko.callsUnknownCounterparty), findsOneWidget);
        expect(find.text('Unknown'), findsNothing);
      });
    });

    testWidgets('with no call on record it says why there is none', (tester) async {
      await tester.pumpWidget(alone(
        const CallHistoryScreen(),
        overrides: [callHistoryProvider.overrideWith((ref) async => const <CallHistoryEntry>[])],
      ));
      await tester.pump();
      await tester.pump();
      expect(findCopy(en.callsEmptyTitle), findsOneWidget);
      // Not a promise that calls made here will show up: none can be made.
      expect(findCopy('This version cannot place or receive calls, so there is nothing to list yet.'), findsOneWidget);
      expect(find.textContaining('will appear'), findsNothing);
    });

    testWidgets('a failed load is told in the app\'s words, not the exception\'s', (tester) async {
      await tester.pumpWidget(alone(
        const CallHistoryScreen(),
        overrides: [
          callHistoryProvider.overrideWith((ref) async => throw StateError('SocketException: errno 111')),
        ],
        locale: 'ko',
      ));
      await tester.pump();
      await tester.pump();
      expect(findCopy(ko.callsUnavailableTitle), findsOneWidget);
      expect(findCopy(ko.callsUnavailableBody), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
    });
  });

  group('a screen for what this build cannot do', () {
    for (final (name, location, screen, title, body) in [
      ('media picker', '/media/$chatConversationId', MediaPickerScreen, en.mediaPickerUnavailableTitle,
          en.mediaPickerUnavailableBody),
      ('voice recorder', '/voice/$chatConversationId', VoiceRecorderScreen, en.voiceRecorderUnavailableTitle,
          en.voiceRecorderUnavailableBody),
      ('story viewer', '/story-viewer/user-$peerHandle', StoryViewerScreen, en.storyViewerUnavailableTitle,
          en.storyViewerUnavailableBody),
    ]) {
      testWidgets('$name: says so, offers nothing that pretends, and leaves', (tester) async {
        await withPhoneApp(tester, identities, location: location, extraRoutes: layoutOnlyRoutes, body: (world) async {
          expect(findCopy(title), findsOneWidget);
          expect(findCopy(body), findsOneWidget);

          // Nothing runs while it is open: no recording time, no story
          // playing through, no grid of pictures that are not there.
          for (var second = 0; second < 8; second++) {
            await tester.pump(const Duration(seconds: 1));
          }
          expect(find.byType(screen), findsOneWidget, reason: 'it did not close or move on by itself');
          expect(find.textContaining(RegExp(r'\d:\d\d')), findsNothing, reason: 'a running time');
          expect(find.byType(GridView), findsNothing);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byType(FilledButton), findsNothing, reason: 'no action that would send something');
          expect(find.byType(OutlinedButton), findsOneWidget);
          expect(world.api.viewedStories, isEmpty, reason: 'nothing was opened, so nothing was viewed');

          await tester.tap(find.text(en.commonClose));
          await pumpFrames(tester);
          expect(find.byType(screen), findsNothing);
          expect(find.byType(ConversationListScreen), findsOneWidget);
        });
      });
    }
  });

  group('emoji picker', () {
    Finder cells() => find.descendant(of: find.byType(GridView), matching: find.byType(InkWell));

    testWidgets('every emoji is a 44 px target on the narrowest phone, in every group', (tester) async {
      await withPhoneApp(tester, identities, location: '/stickers/$chatConversationId', extraRoutes: layoutOnlyRoutes,
          body: (world) async {
        expect(find.byType(Tab), findsNWidgets(EmojiGroup.values.length));
        for (final tab in [en.stickerPickerTabSmileys, en.stickerPickerTabGestures, en.stickerPickerTabSymbols]) {
          await tester.tap(find.text(tab));
          await pumpFrames(tester, frames: 4);
          expect(cells(), findsWidgets);
          for (final cell in cells().evaluate()) {
            final size = (cell.renderObject! as RenderBox).size;
            expect(size.width, greaterThanOrEqualTo(minimumTapTarget), reason: '$tab: a cell is $size');
            expect(size.height, greaterThanOrEqualTo(minimumTapTarget), reason: '$tab: a cell is $size');
          }
        }
        // The grid has the screen: everything under the bar and the tabs.
        final grid = tester.getRect(find.byType(GridView));
        expect(grid.height / phoneSmall.height, greaterThan(0.7));
        expect(grid.bottom, closeTo(phoneSmall.height, 0.5));
      });
    });

    testWidgets('each tab shows its own group, none is for stickers or GIFs, and a pick goes to whoever asked',
        (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(alone(StickerPickerScreen(onEmojiSelected: picked.add)));
      await tester.pump();
      final smiley = emojiCatalog[EmojiGroup.smileys]!.first;
      final gesture = emojiCatalog[EmojiGroup.gestures]!.first;
      expect(find.text(smiley), findsOneWidget);
      expect(find.text(gesture), findsNothing);

      await tester.tap(find.text(en.stickerPickerTabGestures));
      await tester.pumpAndSettle();
      expect(find.text(gesture), findsOneWidget);
      expect(find.text(smiley), findsNothing);

      expect(find.byType(Tab), findsNWidgets(3));
      expect(find.byType(TextField), findsNothing, reason: 'no search: emoji have no names here to search by');
      for (final gone in ['Stickers', 'GIFs']) {
        expect(find.text(gone), findsNothing);
      }
      // An emoji is in one group only, so a tab cannot repeat another.
      final all = [for (final group in emojiCatalog.values) ...group];
      expect(all.toSet(), hasLength(all.length));

      // With someone to hand the emoji to, the picker stays open for more.
      final another = emojiCatalog[EmojiGroup.gestures]![1];
      await tester.tap(find.text(gesture));
      await tester.tap(find.text(another));
      await tester.pump();
      expect(picked, [gesture, another]);
      expect(find.byType(SnackBar), findsNothing, reason: 'picking does something, it does not only say so');
      expect(find.byType(StickerPickerScreen), findsOneWidget);
    });

    testWidgets('opened as a screen, it closes with the picked emoji as its result', (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', extraRoutes: layoutOnlyRoutes,
          body: (world) async {
        final result = pushOver(tester, '/stickers/$chatConversationId');
        await pumpFrames(tester);
        final emoji = emojiCatalog[EmojiGroup.smileys]![3];
        await tester.tap(find.text(emoji));
        await pumpFrames(tester);
        expect(find.byType(StickerPickerScreen), findsNothing);
        expect(result(), emoji);
      });
    });
  });

  group('stories', () {
    testWidgets('lists who has a story up and when, and offers neither to open nor to post one', (tester) async {
      await withPhoneApp(tester, identities, location: '/stories', extraRoutes: layoutOnlyRoutes, body: (world) async {
        expect(findCopy(en.storiesNotice), findsOneWidget);
        // Four people, the one with two stories counted once.
        expect(find.byType(VeilListTileCard), findsNWidgets(4));
        expect(find.text('Selene Park'), findsOneWidget);
        expect(findCopyContaining(en.storiesRowCount(2)), findsOneWidget);
        expect(findCopyContaining(en.storiesRowCount(1)), findsNWidgets(3));
        expect(findCopyContaining(en.storiesAgeHours(2)), findsWidgets);

        // The relay sends a sealed envelope: nothing of a story's content
        // can be on screen, whatever else the response carries.
        for (final caption in ['Sunset over the river tonight', 'Packing is done!', 'Site visit']) {
          expect(find.textContaining(caption), findsNothing);
        }
        expect(find.byIcon(Icons.add_rounded), findsNothing, reason: 'no button to post');

        await tester.tap(find.text('Selene Park'));
        await pumpFrames(tester);
        expect(find.byType(StoryViewerScreen), findsNothing, reason: 'a row has nothing to open');
        expect(find.byType(StoriesScreen), findsOneWidget);
        expect(world.api.viewedStories, isEmpty);
      });
    });

    test('an author is listed once, the newest first, with the age of their newest story', () {
      final now = DateTime(2026, 4, 7, 12);
      StoryFeedEntry story(String id, String user, Duration age) => StoryFeedEntry(
            id: id,
            userId: 'user-$user',
            handle: user,
            createdAt: now.subtract(age),
            expiresAt: now.add(const Duration(hours: 24) - age),
          );
      // In no particular order, as a list may come.
      final authors = storyAuthors([
        story('b', 'noor', const Duration(minutes: 20)),
        story('a', 'selene', const Duration(hours: 5)),
        story('c', 'selene', const Duration(seconds: 30)),
      ]);
      expect([for (final author in authors) (author.handle, author.count)], [('selene', 2), ('noor', 1)]);
      expect(storyAgeLabel(en, authors[0].latest, now: now), en.storiesAgeJustNow);
      expect(storyAgeLabel(en, authors[1].latest, now: now), '20 minutes ago');
      expect(storyAgeLabel(en, now.subtract(const Duration(hours: 1, minutes: 59)), now: now), '1 hour ago');
      expect(storyAgeLabel(ko, now.subtract(const Duration(hours: 23)), now: now), '23시간 전');
      expect(storyAuthors(const []), isEmpty);
    });

    // A story as the relay really lists it: the author's id and handle, the
    // times, and a sealed envelope. No name, no caption, no kind.
    testWidgets('names an author as their chat does, and by handle when there is no chat', (tester) async {
      Map<String, dynamic> record(String handle, {required int minutesAgo}) {
        final posted = DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo));
        return {
          'id': 'story-$handle',
          'userId': 'user-$handle',
          'handle': handle,
          'ciphertext': 'b3BhcXVlIGVudmVsb3Bl',
          'envelopeVersion': 'veil-story-v1',
          'viewedByMe': false,
          'viewCount': null,
          'createdAt': posted.toIso8601String(),
          'expiresAt': posted.add(const Duration(hours: 24)).toIso8601String(),
        };
      }

      await withPhoneApp(tester, identities,
          location: '/stories',
          locale: 'ko',
          extraRoutes: layoutOnlyRoutes,
          prepare: (world) async {
            world.api.storyRecords = [record('stranger', minutesAgo: 40), record(peerHandle, minutesAgo: 3)];
            return null;
          },
          body: (world) async {
        expect(find.text('Selene Park'), findsOneWidget, reason: 'the name the chat with @selene shows');
        expect(find.text('@stranger'), findsOneWidget);
        expect(findCopyContaining(ko.storiesAgeMinutes(3)), findsOneWidget);
        expect(findCopyContaining(ko.storiesAgeMinutes(40)), findsOneWidget);
        expect(find.textContaining('b3BhcXVl'), findsNothing, reason: 'the envelope is not something to show');
        expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
      });
    });

    testWidgets('with no story it says so under the same notice', (tester) async {
      await tester.pumpWidget(alone(
        const StoriesScreen(),
        overrides: [storyFeedProvider.overrideWith((ref) async => const <StoryFeedEntry>[])],
        locale: 'ko',
      ));
      await tester.pump();
      await tester.pump();
      expect(findCopy(ko.storiesNotice), findsOneWidget);
      expect(findCopy(ko.storiesEmptyTitle), findsOneWidget);
      expect(findCopy(ko.storiesEmptyBody), findsOneWidget);
    });
  });

  group('assistant', () {
    testWidgets('answers a question with its prepared answer at once, with no thinking to wait for', (tester) async {
      await tester.pumpWidget(alone(const AiChatScreen()));
      await tester.pump();
      expect(find.text(en.aiDemoBannerBody), findsOneWidget);
      expect(findCopy(en.aiIntro), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(AiTopic.values.length));
      expect(find.byType(TextField), findsNothing, reason: 'nothing would read what is typed');

      await tester.tap(find.widgetWithText(ActionChip, en.aiQuestionCalls));
      // The very next frame: no timer stands between question and answer.
      await tester.pump();
      expect(findCopy(en.aiAnswerCalls), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Thinking'), findsNothing);
      // Asked, it is in the conversation and no longer among the questions.
      expect(findCopy(en.aiQuestionCalls), findsOneWidget);
      expect(find.widgetWithText(ActionChip, en.aiQuestionCalls), findsNothing);
      expect(find.byType(ActionChip), findsNWidgets(AiTopic.values.length - 1));
      await tester.pumpAndSettle();

      // Clearing brings every question back and takes the answers away.
      await tester.tap(find.byTooltip(en.aiClearTooltip));
      await tester.pump();
      expect(findCopy(en.aiAnswerCalls), findsNothing);
      expect(find.byType(ActionChip), findsNWidgets(AiTopic.values.length));
      expect(find.text(en.aiDemoBannerBody), findsOneWidget, reason: 'the disclosure never leaves');
    });

    testWidgets('speaks Korean in a Korean app, question and answer', (tester) async {
      usePhoneView(tester, phoneMedium);
      await tester.pumpWidget(alone(const AiChatScreen(), locale: 'ko'));
      await tester.pump();
      final foreign = otherLanguageTextsOnScreen(tester, 'ko');
      for (final (question, answer) in [
        (ko.aiQuestionBackup, ko.aiAnswerBackup),
        (ko.aiQuestionNewDevice, ko.aiAnswerNewDevice),
        (ko.aiQuestionGroups, ko.aiAnswerGroups),
        (ko.aiQuestionCalls, ko.aiAnswerCalls),
      ]) {
        await tester.tap(find.widgetWithText(ActionChip, question));
        // The conversation scrolls to what was just answered.
        await tester.pumpAndSettle();
        expect(findCopy(answer), findsOneWidget);
        foreign.addAll(otherLanguageTextsOnScreen(tester, 'ko'));
      }
      expect(find.byType(ActionChip), findsNothing, reason: 'every question was asked');
      expect(foreign, isEmpty);
    });
  });

  group('attachment screen', () {
    testWidgets('says what it sends, and what the typed name decides', (tester) async {
      await withPhoneApp(tester, identities,
          location: '/attachment/$chatConversationId', extraRoutes: layoutOnlyRoutes, body: (world) async {
        expect(findCopy(en.attachmentPlaceholderNotice), findsOneWidget);
        expect(findCopy(en.attachmentNameCaption('application/octet-stream')), findsOneWidget);
        // Nothing about a lifecycle the screen does not show happening.
        expect(find.byType(VeilStepRow), findsNothing);
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(find.byType(VeilStatusPill), findsNothing);

        await tester.enterText(find.byType(TextField), 'lease-scan.PDF');
        await tester.pump();
        expect(findCopy(en.attachmentNameCaption('application/pdf')), findsOneWidget);

        // No name, nothing to send under.
        FilledButton send() => tester.widget<FilledButton>(find.byType(FilledButton));
        expect(send().onPressed, isNotNull);
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pump();
        expect(send().onPressed, isNull);
        expect(find.byType(AttachmentPreviewScreen), findsOneWidget);
      });
    });
  });
}
