import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// The profile on a phone: the handle and the nickname with its edit button
// on the first screenful, and under them the one note on what the relay
// keeps of a person.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  for (final (locale, l10n) in [('en', en), ('ko', ko)]) {
    testWidgets('opens on the handle and the nickname, with the note on the relay under them ($locale)',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/profile', locale: locale, body: (world) async {
        final handle = tester.getRect(find.text('@$selfHandle'));
        final nickname = tester.getRect(find.text(selfDisplayName).last);
        final edit = tester.getRect(find.widgetWithText(TextButton, l10n.profileEditNickname));
        final note = tester.getRect(findCopy(l10n.profilePrivacyTitle));
        expect(handle.bottom, lessThan(nickname.top));
        expect(edit.bottom, lessThanOrEqualTo(640 * 0.75), reason: 'editing is on the first screenful');
        expect(edit.height, greaterThanOrEqualTo(44));
        expect(edit.bottom, lessThan(note.top), reason: 'the explanation comes after');
        expect(findCopy(l10n.profileHandleCaption), findsOneWidget);
        expect(findCopy(l10n.profileNicknameCaption), findsOneWidget);
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(await otherLanguageTextsOfScreen(tester, locale), isEmpty);
      });
    });
  }

  // The relay keeps the handle, the devices and who was added as a contact:
  // the note is about the profile, which it does not keep, and no wider.
  test('the note on the relay claims no more than that it keeps no profile', () {
    expect(en.profilePrivacyTitle.toLowerCase(), contains('profile'));
    expect(en.profilePrivacyTitle.toLowerCase(), isNot(contains('nothing')));
    expect(ko.profilePrivacyTitle, contains('프로필'));
  });

  // One thing, one word: the name only this device knows, the user's own on
  // the profile and a contact's in the contacts.
  test('a nickname has one Korean word on the profile and in the contacts', () {
    for (final text in [
      ko.profileNicknameLabel,
      ko.profileNicknameSaved,
      ko.profileEditNickname,
      ko.profilePrivacyBody,
      ko.contactsNicknameLabel,
      ko.contactsEditNickname,
      ko.contactsSaveNickname,
      ko.contactsNicknameCaption,
    ]) {
      expect(text, contains('별명'));
      expect(text, isNot(contains('닉네임')));
    }
  });

  testWidgets('the nickname is edited in place: cancel keeps it, an empty one clears it', (tester) async {
    await withPhoneApp(tester, identities, location: '/profile', keyboardHeight: 300, body: (world) async {
      String? nickname() => world.container.read(appSessionProvider).displayName;
      // With the keyboard up a 360x640 phone shows a third of the screen:
      // what is tapped is scrolled to first, as a thumb would.
      Future<void> tapShown(Finder finder) async {
        // A field that was just typed into scrolls its caret into view for
        // a moment, and a list that is scrolling takes no tap.
        await pumpFrames(tester, frames: 2);
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
        await pumpFrames(tester, frames: 2);
        await tester.tap(finder);
        await pumpFrames(tester, frames: 3);
      }

      final edit = find.text(en.profileEditNickname, skipOffstage: false);
      final save = find.widgetWithText(FilledButton, en.profileSaveNickname, skipOffstage: false);
      final field = find.byType(TextField, skipOffstage: false);
      await tapShown(edit);
      expect(tester.widget<TextField>(field).controller!.text, selfDisplayName);
      // The button that saves can be brought above the keyboard.
      await tester.ensureVisible(save);
      await tester.pump();
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300));

      await tester.enterText(field, 'Someone else');
      await tapShown(find.text(en.profileCancel, skipOffstage: false));
      expect(nickname(), selfDisplayName);
      expect(field, findsNothing);

      await tapShown(edit);
      await tester.enterText(field, '  ');
      await tapShown(save);
      expect(nickname(), isNull);
      expect(find.text(en.profileNicknameNotSet, skipOffstage: false), findsOneWidget);
      expect(findCopy(en.profileNicknameSaved), findsOneWidget);
    });
  });
}
