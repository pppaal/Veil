import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_index.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/contacts/data/contacts_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import '../support/fake_relay.dart';
import 'phone_app.dart';

// The contacts tab on a phone: the list is the screen, adding a contact is
// an action of the bar, and the sheets (add, actions, nickname) keep their
// button above the keyboard.

ContactEntry _contact(String label) =>
    ContactEntry(handle: 'h', displayName: label, nickname: null, avatarPath: null, addedAt: DateTime.utc(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder rows() => find.byType(VeilConversationCard);
  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  group('the index of the list', () {
    test('files a Korean name under its first consonant, a doubled one under the single', () {
      expect(contactIndexLetter('김서연'), 'ㄱ');
      expect(contactIndexLetter('한지우'), 'ㅎ');
      expect(contactIndexLetter('까치'), 'ㄱ');
      expect(contactIndexLetter('쌍둥이'), 'ㅅ');
      expect(contactIndexLetter('힣'), 'ㅎ');
    });

    test('files other names under their capital, and what is no letter under #', () {
      expect(contactIndexLetter('mira'), 'M');
      expect(contactIndexLetter('  Rowan'), 'R');
      expect(contactIndexLetter('Élodie'), 'É');
      expect(contactIndexLetter('007'), '#');
      expect(contactIndexLetter('_x'), '#');
      expect(contactIndexLetter(''), '#');
    });

    test('orders the letters, # last, and the names under each', () {
      final sections = sectionContacts([
        for (final name in ['mira', '9lives', '한지우', 'Maximilian', '김서연', 'noor']) _contact(name),
      ]);
      expect([for (final section in sections) section.letter], ['M', 'N', 'ㄱ', 'ㅎ', '#']);
      expect([for (final contact in sections.first.contacts) contact.label], ['Maximilian', 'mira']);
      // A Korean list starts at ㄱ.
      final korean = sectionContacts([for (final name in ['mira', '9lives', '한지우', '김서연']) _contact(name)], hangulFirst: true);
      expect([for (final section in korean) section.letter], ['ㄱ', 'ㅎ', 'M', '#']);
    });

    test('a search matches the name or the handle, whatever the case', () {
      final contacts = [
        ContactEntry(handle: 'seoyeon', displayName: '김서연', nickname: null, avatarPath: null, addedAt: DateTime.utc(2026)),
        ContactEntry(handle: 'rowan', displayName: 'Rowan', nickname: 'Ro', avatarPath: null, addedAt: DateTime.utc(2026)),
      ];
      expect(filterContacts(contacts, ' SEO '), [contacts[0]]);
      expect(filterContacts(contacts, 'ro'), [contacts[1]]);
      expect(filterContacts(contacts, '서연'), [contacts[0]]);
      expect(filterContacts(contacts, ''), contacts);
      expect(filterContacts(contacts, 'zz'), isEmpty);
    });
  });

  testWidgets('the list is the screen: adding is in the bar, the rows start under the search', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      const barBottom = 24.0 + 52;
      final add = tester.getRect(find.byTooltip(en.contactsAdd));
      expect(add.bottom, lessThanOrEqualTo(barBottom), reason: 'the add action is in the bar');
      expect(add.shortestSide, greaterThanOrEqualTo(44));

      final tabs = tester.getRect(find.text(en.navContacts).last).top;
      final firstRow = tester.getRect(rows().first);
      expect(tester.getRect(find.byType(TextField)).bottom, lessThan(firstRow.top));
      expect(firstRow.top, lessThan(640 * 0.3), reason: 'nothing but the search is above the contacts');
      final whole = rows().evaluate().where((row) => tester.getRect(find.byWidget(row.widget)).bottom <= tabs).length;
      expect(whole, greaterThanOrEqualTo(4), reason: 'contacts whole on the first screenful of a 360x640 phone');

      // What the relay keeps of the list is said, under the list.
      expect(find.byType(VeilInlineBanner), findsNothing);
      await scrollToEnd(tester);
      expect(findCopy(en.contactsNotice), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('files Korean names under consonants, which lead the list in a Korean app', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', locale: 'ko', size: phoneLarge, body: (world) async {
      const prefix = 'contacts-index-';
      final headers = <String>[];
      void collect() {
        for (final element in find.byType(Padding).evaluate()) {
          if (element.widget.key case ValueKey<String>(:final value) when value.startsWith(prefix)) {
            final letter = value.substring(prefix.length);
            if (!headers.contains(letter)) headers.add(letter);
          }
        }
      }

      collect();
      await scrollToEnd(tester, onPage: (_) async => collect());
      // The consonants first in a Korean app: 김서연 under ㄱ, 한지우 under ㅎ,
      // and neither under its whole first syllable.
      expect(headers, ['ㄱ', 'ㅎ', 'M', 'N', 'R', 'S', 'T']);
      expect(find.text('ㅎ'), findsOneWidget);

      // A consonant alone is a small glyph: at the size of a caption, in
      // the faintest text colour, ㄱ and ㅎ were hard to tell.
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await pumpFrames(tester, frames: 2);
      final index = tester.widget<Text>(find.text('ㄱ')).style!;
      expect(index.fontSize, greaterThanOrEqualTo(14));
      expect(index.color, isNot(tester.element(find.text('ㄱ')).veilPalette.textSubtle));
    });
  });

  testWidgets('a search narrows the list by name or handle, and says when nothing matches', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      await tester.enterText(find.byType(TextField), 'se');
      await pumpFrames(tester, frames: 2);
      // Selene by name and handle, 김서연 by her handle (seoyeon).
      expect(rows(), findsNWidgets(2));
      expect(find.text('Selene Park'), findsOneWidget);
      expect(find.text('김서연 (디자인팀)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nobody');
      await pumpFrames(tester, frames: 2);
      expect(rows(), findsNothing);
      expect(find.text(en.contactsEmptySearchTitle), findsOneWidget);

      await tester.tap(find.byTooltip(en.contactsSearchClear));
      await pumpFrames(tester, frames: 2);
      expect(rows(), findsWidgets);
      expect(find.text(en.contactsEmptySearchTitle), findsNothing);
    });
  });

  testWidgets('adding a contact: the button waits for a handle, a refusal is said in the sheet, above the keyboard',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', keyboardHeight: 300, prepare: (world) async {
      world.relay.addParty(
        RelayParty(handle: 'icarus', userId: 'user-icarus', deviceId: 'dev-icarus', identity: identities.peer),
      );
      return null;
    }, body: (world) async {
      await tester.tap(find.byTooltip(en.contactsAdd));
      await pumpFrames(tester, frames: 4);
      final save = inSheet(find.byType(FilledButton));
      final fields = inSheet(find.byType(TextField));
      expect(fields, findsNWidgets(2));
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'nothing to save yet');
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300), reason: 'the button is above the keyboard');
      expect(findCopy(en.contactsNotice), findsOneWidget, reason: 'what the relay keeps is said where one adds');

      // A handle the relay does not know.
      await tester.enterText(fields.first, 'nobody');
      await tester.pump();
      await tester.tap(save);
      await pumpFrames(tester, frames: 4);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'the sheet stays for another try');
      expect(inSheet(findCopy(en.contactsAddFailed)), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300), reason: 'still above the keyboard');
      expect(world.api.addedContacts, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.enterText(fields.first, '@icarus');
      await tester.pump();
      expect(inSheet(findCopy(en.contactsAddFailed)), findsNothing, reason: 'a new handle clears the refusal');
      await tester.enterText(fields.last, 'Ica');
      await tester.tap(save);
      await pumpFrames(tester, frames: 6);
      expect(find.byType(BottomSheet), findsNothing);
      expect(world.api.addedContacts, ['icarus']);
      expect(findCopy(en.contactsAdded('icarus')), findsOneWidget);
      expect(find.text('Ica'), findsOneWidget, reason: 'listed under the name it was given');
    });
  });

  testWidgets('a contact\'s nickname is changed from its sheet, and only this device learns it', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', keyboardHeight: 300, body: (world) async {
      await tester.tap(find.text('Mira'));
      await pumpFrames(tester, frames: 4);
      expect(inSheet(find.text('@mira')), findsOneWidget);
      await tester.tap(find.text(en.contactsEditNickname));
      await pumpFrames(tester, frames: 6);

      final save = inSheet(find.widgetWithText(FilledButton, en.contactsSaveNickname));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300), reason: 'the button is above the keyboard');
      await tester.enterText(inSheet(find.byType(TextField)), 'Mimi');
      await tester.tap(save);
      await pumpFrames(tester, frames: 6);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Mimi'), findsOneWidget);
      expect(find.text('Mira'), findsNothing);
      final stored = await ContactNicknames(world.storage.scoped(SecureScope.contacts)).readAll();
      expect(stored, {'mira': 'Mimi'});
      expect(world.api.addedContacts, isEmpty, reason: 'the relay is not told');
    });
  });

  testWidgets('a contact is removed from its sheet, and a chat with one opens from it', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      await tester.tap(find.text('Mira'));
      await pumpFrames(tester, frames: 4);
      // Nothing in the sheet pretends to a profile the relay does not keep.
      expect(inSheet(find.byType(FilledButton)), findsOneWidget);
      expect(inSheet(find.byType(OutlinedButton)), findsNWidgets(2));
      await tester.tap(find.text(en.contactsRemove));
      await pumpFrames(tester, frames: 6);
      expect(world.api.removedContacts, {'mira'});
      expect(find.text('Mira'), findsNothing);
      expect(findCopy(en.contactsRemoved('Mira')), findsOneWidget);

      await tester.tap(find.text('Noor Al-Hashimi'));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.text(en.contactsStartChat));
      await pumpFrames(tester, frames: 8);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, 'conv-noor');
    });
  });
}
