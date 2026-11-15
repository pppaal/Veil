import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_labels.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_screen_intro.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/screen_cases.dart' show layoutOnlyRoutes;
import '../support/copy_finder.dart';
import 'phone_app.dart';

// What the screens around the chat say on a phone, and in which order: a
// Korean app speaks Korean on the screens with the destructive actions, a
// pending identity change comes first on the screen that reviews it, and a
// Korean headline wraps between its words.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The safety number is derived on a background isolate, which only real
  // time moves forward.
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byType(VeilLoadingBlock);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  group('settings', () {
    // Names the user or the platform gave are no locale's to translate, and
    // the language check leaves them out (notOwnCopy): nothing else on the
    // screen may be English.
    testWidgets('in a Korean app only names are not Korean', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', body: (world) async {
        final shown = <String>{};
        void collect() {
          for (final element in find.byType(Text).evaluate()) {
            if ((element.widget as Text).data case final text?) shown.add(text);
          }
        }

        collect();
        final foreign = otherLanguageTextsOnScreen(tester, 'ko');
        await scrollToEnd(tester, onPage: (_) async {
          collect();
          foreign.addAll(otherLanguageTextsOnScreen(tester, 'ko'));
        });
        expect(foreign, isEmpty);
        expect(shown, containsAll(['Atlas Moreau', 'Pixel 9 Pro Fold', 'MacBook Air', 'Android']),
            reason: 'the device graph was on screen');
      });
    });

    testWidgets('says what each destructive action does, in Korean', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', body: (world) async {
        final seen = <String>{};
        void collect() {
          for (final element in find.byType(Text).evaluate()) {
            if ((element.widget as Text).data case final text?) seen.add(text);
          }
        }

        collect();
        await scrollToEnd(tester, onPage: (_) async => collect());
        // What a text says, without the joiners it is drawn with.
        final said = seen.map(plainCopy).toSet();
        final l10n = lookupAppLocalizations(const Locale('ko'));
        for (final text in [
          '보안',
          '세션',
          '그래프 요약',
          '이 기기',
          '해지됨',
          '장기 미사용 1대',
          '접속 4월 2일 (UTC)',
          l10n.settingsDestructiveNoticeBody,
          l10n.settingsWipeLocalSubtitle,
          l10n.settingsRevokeSubtitle,
          l10n.settingsLogoutSubtitle,
        ]) {
          expect(said, contains(text));
        }
      });
    });

    testWidgets('in an English app nothing is Korean, and the device graph reads as before', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        expect(find.text('GRAPH SUMMARY'), findsOneWidget);
        expect(find.text('1 stale'), findsOneWidget);
        expect(find.text('Seen Apr 2 (UTC)'), findsWidgets);
        expect(await otherLanguageTextsOfScreen(tester, 'en'), isEmpty);
      });
    });

    testWidgets('asks for the phrase to type in the app\'s language', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', body: (world) async {
        final wipe = find.text('이 기기에서 로컬 상태 삭제');
        await tester.dragUntilVisible(wipe, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        await tester.tap(wipe);
        await pumpFrames(tester, frames: 3);
        expect(find.text('계속하려면 다음을 입력하세요: WIPE'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '로컬 상태 삭제'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await pumpFrames(tester, frames: 3);
      });
    });
  });

  group('device transfer', () {
    testWidgets('the old device says in Korean that its code is ready', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: '/device-transfer',
        locale: 'ko',
        transferStarted: true,
        body: (world) async {
          // The transfer code is data, which the check leaves out.
          expect(await otherLanguageTextsOfScreen(tester, 'ko'), isEmpty);
          // "Code", as every other line of the screen calls it; not "token".
          expect(findCopy('이전 세션을 열었습니다. 코드가 준비되었습니다.', skipOffstage: false), findsOneWidget);
        },
      );
    });

    test('every outcome of the old device has words in both languages', () {
      const outcomes = <TransferStatus>[
        TransferNeedsApi(),
        TransferTokenReady(),
        TransferNotStarted(),
        TransferClaimCodeMissing(),
        TransferClaimNotWaiting('claim-7'),
        TransferClaimApproved('claim-7', 'AB12 CD34'),
      ];
      for (final locale in ['en', 'ko']) {
        final l10n = lookupAppLocalizations(Locale(locale));
        final labels = [for (final outcome in outcomes) transferStatusLabel(l10n, outcome)!];
        expect(labels.toSet(), hasLength(outcomes.length), reason: locale);
        expect(labels[4], contains('claim-7'));
        expect(labels[5], allOf(contains('claim-7'), contains('AB12 CD34')));
        expect(transferStatusLabel(l10n, null), isNull);
      }
      final en = lookupAppLocalizations(const Locale('en'));
      expect(transferStatusLabel(en, const TransferClaimApproved('c', 'f')), 'Approved claim c on old device. Key fingerprint: f');
    });
  });

  // The attachment screen's feature is switched off, so the app has no
  // route to it; the screen is still built and tested through the test-only
  // routes.
  group('attachment', () {
    testWidgets('speaks Korean, and says what this build sends', (tester) async {
      await withPhoneApp(tester, identities, location: '/attachment/$chatConversationId', locale: 'ko',
          extraRoutes: layoutOnlyRoutes, body: (world) async {
        // The file's name and its type are data, which the check leaves out.
        expect(await otherLanguageTextsOfScreen(tester, 'ko'), isEmpty);
      });
    });

    testWidgets('no longer says the build runs on mock crypto', (tester) async {
      await withPhoneApp(tester, identities, location: '/attachment/$chatConversationId',
          extraRoutes: layoutOnlyRoutes, body: (world) async {
        final seen = <String>{};
        void collect() {
          for (final element in find.byType(Text).evaluate()) {
            if ((element.widget as Text).data case final text?) seen.add(text);
          }
        }

        collect();
        await scrollToEnd(tester, onPage: (_) async => collect());
        expect(seen.where((text) => text.toLowerCase().contains('mock')), isEmpty);
        expect(seen.where((text) => text.contains('placeholder file')), hasLength(1),
            reason: 'that it sends a placeholder is said once');
        expect(seen, contains('Encrypt and send'));
      });
    });
  });

  group('safety number with a pending identity change', () {
    const change = ChatAttention(identityChanged: true);
    const location = '/safety-numbers/$chatConversationId';

    testWidgets('a phone opens on the warning, before anything else', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = tester.getRect(find.text("This contact's identity key changed"));
        final intro = tester.getRect(find.byType(VeilScreenIntro));
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(warning.bottom, lessThan(intro.top));
        expect(warning.top, lessThan(screenHeight(tester) / 2), reason: 'on the first screenful');
        expect(find.text("This contact's identity key changed"), findsOneWidget, reason: 'said once');
      });
    });

    // The number to compare is the new one, so it comes first with the
    // decision under it; the pinned number follows for reference.
    testWidgets('says which number is the new one and which the current, the new one first', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final current = find.text('CURRENT SAFETY NUMBER', skipOffstage: false);
        final next = find.text('NEW SAFETY NUMBER', skipOffstage: false);
        final decide = find.text('Re-verify with new key', skipOffstage: false);
        expect(next, findsOneWidget);
        final newTop = tester.getTopLeft(next).dy;
        final decideTop = tester.getTopLeft(decide).dy;
        await tester.dragUntilVisible(current, find.byType(ListView), const Offset(0, -200));
        expect(current, findsOneWidget);
        expect(newTop, lessThan(decideTop));
        expect(find.text('SAFETY NUMBER', skipOffstage: false), findsNothing);
        // Scrolled by now: compared within one frame.
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('a wide window opens on the warning too, with the new number before the current one', (tester) async {
      const wide = PhoneSize(900, 1400, topInset: 0, bottomInset: 0);
      await withPhoneApp(tester, identities, size: wide, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = find.text("This contact's identity key changed", skipOffstage: false);
        final current = find.text('CURRENT SAFETY NUMBER', skipOffstage: false);
        final next = find.text('NEW SAFETY NUMBER', skipOffstage: false);
        expect(tester.getTopLeft(warning).dy, lessThan(tester.getTopLeft(next).dy));
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('with no change there is one number, under its plain label', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        await awaitSafetyNumber(tester);
        expect(find.text('SAFETY NUMBER', skipOffstage: false), findsOneWidget);
        expect(find.text("This contact's identity key changed", skipOffstage: false), findsNothing);
      });
    });
  });

  group('a Korean headline', () {
    // Every word of the headline is on one line: no syllable is left alone.
    void expectWordsWhole(WidgetTester tester) {
      final title = find.descendant(
        of: find.byType(VeilScreenIntro),
        matching: find.byWidgetPredicate((widget) => widget is Text && widget.semanticsLabel != null),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title.first, matching: find.byType(RichText)),
      );
      final shown = paragraph.text.toPlainText();
      final words = RegExp(r'\S+').allMatches(shown).toList();
      expect(words.length, greaterThan(1));
      for (final word in words) {
        final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
        expect({for (final box in boxes) box.top}, hasLength(1), reason: '"${word[0]}" is split over lines in "$shown"');
      }
      expect(paragraph.size.width, lessThanOrEqualTo(360));
    }

    for (final (name, location, account) in [
      ('create account', '/create-account', LayoutAccount.signedOut),
      ('security status', '/security-status', LayoutAccount.signedIn),
      ('the app lock', '/lock', LayoutAccount.locked),
    ]) {
      testWidgets('wraps between words on $name', (tester) async {
        await withPhoneApp(tester, identities, location: location, account: account, locale: 'ko', body: (world) async {
          expectWordsWhole(tester);
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('wraps between words on the safety number', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$chatConversationId', locale: 'ko',
          body: (world) async {
        await awaitSafetyNumber(tester);
        expectWordsWhole(tester);
      });
    });

    test('is the same text to a screen reader and to a search, with joiners only for drawing', () {
      expect(veilKeepWordsWhole('No backup. No recovery.'), 'No backup. No recovery.');
      const title = '이 기기가 당신의 신원이 됩니다.';
      final shown = veilKeepWordsWhole(title);
      expect(shown.replaceAll('⁠', ''), title);
      expect(shown.split(' '), hasLength(title.split(' ').length), reason: 'spaces stay where a line may break');
      expect(shown, contains('됩⁠니⁠다⁠.'));
      // A word with a Latin part is one word too; a Latin word is left alone.
      expect(veilKeepWordsWhole('VEIL은 복구 없음'), 'V⁠E⁠I⁠L⁠은 복⁠구 없⁠음');
      expect(veilKeepWordsWhole('Selene Park님과'), 'Selene P⁠a⁠r⁠k⁠님⁠과');
    });

    testWidgets('still breaks a word that is wider than the line', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final word = '가나다라마바사아자차카타파하' * 4;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 200, child: Text(veilKeepWordsWhole(word), style: const TextStyle(fontSize: 20)))),
      ));
      final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
      expect(paragraph.size.width, lessThanOrEqualTo(200));
      expect(paragraph.size.height, greaterThan(40), reason: 'it took more than one line');
      expect(tester.takeException(), isNull);
    });
  });

  group('privacy consent', () {
    // The framework's tap target check never measured this row: it starts
    // at the left edge of its column. It was 24 px tall in Korean.
    testWidgets('the consent sentence and its box are one target, 44 px tall, and either toggles it',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/privacy-consent', account: LayoutAccount.signedOut, locale: 'ko',
          body: (world) async {
        // Under the notice from the start: nothing is scrolled to reach it.
        final sentence = findCopy('위 개인정보 수집·이용에 동의합니다. (필수)');
        expect(sentence, findsOneWidget);

        final row = find.ancestor(of: sentence, matching: find.byType(MergeSemantics)).first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
        expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), isEmpty);

        bool checked() => tester.widget<Checkbox>(find.byType(Checkbox)).value!;
        FilledButton proceed() => tester.widget(find.widgetWithText(FilledButton, '동의하고 계속하기'));
        expect(checked(), isFalse);
        expect(proceed().onPressed, isNull);

        await tester.tap(sentence);
        await tester.pump();
        expect(checked(), isTrue);
        expect(proceed().onPressed, isNotNull);

        // Just under the sentence, inside the row's own padding.
        await tester.tapAt(tester.getRect(row).bottomCenter.translate(0, -3));
        await tester.pump();
        expect(checked(), isFalse);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(checked(), isTrue);
      });
    });
  });

  group('an empty chat', () {
    const location = '/chat/$emptyChatConversationId';

    testWidgets('above the keyboard shows its words and its button whole, without the icon', (tester) async {
      await withPhoneApp(tester, identities, location: location, keyboardHeight: 300, body: (world) async {
        final area = onScreen(tester, find.byType(ChatMessageList));
        for (final finder in [
          find.text('No messages yet'),
          find.textContaining('Send the first message'),
          find.widgetWithText(FilledButton, 'Send'),
        ]) {
          final box = tester.renderObject<RenderBox>(finder);
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.top, greaterThanOrEqualTo(area.top), reason: '$finder');
          expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: '$finder');
        }
        expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with the whole screen shows its icon too', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
      });
    });
  });
}
