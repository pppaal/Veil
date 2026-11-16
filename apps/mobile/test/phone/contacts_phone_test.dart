import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_index.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/contacts/data/contacts_providers.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart' show peerNames;
import '../support/copy_finder.dart';
import '../support/fake_relay.dart';
import 'phone_app.dart';

// The contacts tab on a phone: the list is the screen, adding a contact is
// an action of the bar, and the sheets (add, actions, nickname) keep their
// button above the keyboard. The add sheet is a field, an optional name and
// a button, with no note under them (Threema, Session).

ContactEntry _contact(String label) =>
    ContactEntry(handle: 'h', nickname: label, avatarPath: null, addedAt: DateTime.utc(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder rows() => find.byType(ContactRow);
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
        ContactEntry(handle: 'seoyeon', nickname: '김서연', avatarPath: null, addedAt: DateTime.utc(2026)),
        ContactEntry(handle: 'rowan', nickname: 'Ro', avatarPath: null, addedAt: DateTime.utc(2026)),
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

      // Nothing but the list: no notice above it or under it.
      expect(find.byType(VeilNotice), findsNothing);
      await scrollToEnd(tester);
      expect(find.textContaining('server'), findsNothing);
      // Full-bleed rows around a 40 avatar, with room above and below it.
      final first = tester.getRect(rows().first);
      expect(first.left, 0);
      expect(first.width, 360);
      expect(first.height, greaterThanOrEqualTo(52));
      expect(tester.takeException(), isNull);
    });
  });

  // As Telegram's contacts: one run of names in order, no letter over them.
  testWidgets('lists the names in one run, in order, with no letter headers', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', size: phoneLarge, body: (world) async {
      final labels = <String>[];
      void collect() {
        for (final row in tester.widgetList<ContactRow>(rows())) {
          if (!labels.contains(row.contact.label)) labels.add(row.contact.label);
        }
      }

      collect();
      await scrollToEnd(tester, onPage: (_) async => collect());
      final sorted = [...labels]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(labels, sorted);
      expect(labels.length, greaterThan(4));
      for (final group in tester.widgetList<VeilGroup>(find.byType(VeilGroup, skipOffstage: false))) {
        expect(group.header, isNull, reason: 'no letter heads a run');
      }
      expect(find.byKey(const ValueKey('contacts-list'), skipOffstage: false), findsOneWidget);
    });
  });

  // M26: an account with no name is its handle, once, with its "@".
  testWidgets('a contact with no name is one line, its @handle', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', size: phoneLarge, body: (world) async {
      final row = find.byWidgetPredicate((widget) => widget is ContactRow && widget.contact.handle == 'tom_walsh',
          skipOffstage: false);
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await pumpFrames(tester, frames: 2);
      expect(find.descendant(of: row, matching: find.text('@tom_walsh')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('tom_walsh')), findsNothing);
      // A contact with a name keeps it over the handle.
      final sam = tester.widget<ContactRow>(
          find.byWidgetPredicate((widget) => widget is ContactRow && widget.contact.handle == peerHandle, skipOffstage: false));
      expect(sam.contact.title, 'Sam Rivera');
      expect(sam.contact.handleLine, '@$peerHandle');
    });
  });

  testWidgets('a search narrows the list by name or handle, and says when nothing matches', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      await tester.enterText(find.byType(TextField), 'ri');
      await pumpFrames(tester, frames: 2);
      // Sam Rivera and Priya Nair by name, Priya by her handle as well.
      expect(rows(), findsNWidgets(2));
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('Priya Nair'), findsOneWidget);

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
      // No helper and no footer: the field, the name and the button.
      expect(tester.widget<TextField>(fields.first).decoration!.helperText, isNull);
      expect(inSheet(find.textContaining('server', skipOffstage: false)), findsNothing);

      // A handle the relay does not know.
      await tester.enterText(fields.first, 'nobody');
      await tester.pump();
      await tester.tap(save);
      await pumpFrames(tester, frames: 4);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'the sheet stays for another try');
      // Not found is said as such; any other failure is contactsAddFailed.
      expect(inSheet(findCopy(en.safetyAccountNotFound('nobody'))), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300), reason: 'still above the keyboard');
      expect(world.api.addedContacts, isEmpty);
      expect(tester.takeException(), isNull);

      // The refusal is the handle field's error.
      expect(tester.widget<TextField>(fields.first).decoration!.errorText, en.safetyAccountNotFound('nobody'));
      await tester.enterText(fields.first, '@icarus');
      await pumpFrames(tester, frames: 2);
      expect(tester.widget<TextField>(fields.first).decoration!.errorText, isNull,
          reason: 'a new handle clears the refusal');
      expect(inSheet(findCopy(en.safetyAccountNotFound('nobody'))), findsNothing);
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
      // The first row: with the keyboard up a 360x640 phone builds few.
      const name = 'Alexandra Montgomery-Whitfield';
      await tester.tap(find.text(name));
      await pumpFrames(tester, frames: 4);
      expect(inSheet(find.text('@alexandra')), findsOneWidget);
      await tester.tap(find.text(en.contactsEditNickname));
      await pumpFrames(tester, frames: 6);
      final before = await ContactNicknames(world.storage.scoped(SecureScope.contacts)).readAll();

      final save = inSheet(find.widgetWithText(FilledButton, en.contactsSaveNickname));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300), reason: 'the button is above the keyboard');
      await tester.enterText(inSheet(find.byType(TextField)), 'Alexa');
      await tester.tap(save);
      await pumpFrames(tester, frames: 6);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Alexa'), findsOneWidget);
      expect(find.text(name), findsNothing);
      final stored = await ContactNicknames(world.storage.scoped(SecureScope.contacts)).readAll();
      // That one name changed, and nothing else the phone holds; it still
      // names the account it named.
      expect({for (final MapEntry(:key, :value) in stored.entries) key: value.name}, {
        for (final MapEntry(key: handle, value: name) in peerNames.entries)
          if (name != null) handle: name,
        'alexandra': 'Alexa',
      });
      expect({for (final MapEntry(:key, :value) in stored.entries) key: value.userId},
          {for (final MapEntry(:key, :value) in before.entries) key: value.userId});
      expect(world.api.addedContacts, isEmpty, reason: 'the relay is not told');
    });
  });

  testWidgets('a contact is removed from its sheet, and a chat with one opens from it', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      await tester.tap(find.text('Lena Fischer'));
      await pumpFrames(tester, frames: 4);
      // Five rows under the contact, led by Message, and only Block in red;
      // nothing in the sheet pretends to a profile the server does not keep.
      final actionRows = inSheet(find.byType(VeilRow));
      expect([for (final row in tester.widgetList<VeilRow>(actionRows)) row.title],
          [en.contactsStartChat, en.contactsEditNickname, en.contactsRemove, en.reportAction, en.blockAction]);
      expect(tester.widget<VeilRow>(inSheet(find.widgetWithText(VeilRow, en.blockAction))).destructive, isTrue);
      expect(tester.widget<VeilRow>(inSheet(find.widgetWithText(VeilRow, en.contactsRemove))).destructive, isFalse);
      expect(inSheet(find.byType(FilledButton)), findsNothing);
      await tester.tap(find.text(en.contactsRemove));
      await pumpFrames(tester, frames: 6);
      expect(world.api.removedContacts, {emptyChatPeerHandle});
      expect(find.text('Lena Fischer'), findsNothing);
      expect(findCopy(en.contactsRemoved('Lena Fischer')), findsOneWidget);

      await tester.tap(find.text('Jonas Weber'));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.text(en.contactsStartChat));
      await pumpFrames(tester, frames: 8);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, timerChatConversationId);
    });
  });

  // M26: an account with no name is "@tom_walsh" wherever it is named
  // outside a Chats row, as its row, the add toast and the block toast say.
  testWidgets('a contact with no name is removed, and read out, as its @handle', (tester) async {
    final semantics = tester.ensureSemantics();
    await withPhoneApp(tester, identities, location: '/contacts', size: phoneLarge, body: (world) async {
      final row = find.byWidgetPredicate((widget) => widget is ContactRow && widget.contact.handle == 'tom_walsh',
          skipOffstage: false);
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await pumpFrames(tester, frames: 2);
      expect(find.bySemanticsLabel(en.contactsRowSemantics('@tom_walsh')), findsOneWidget);
      expect(find.bySemanticsLabel(en.contactsRowSemantics('tom_walsh')), findsNothing);

      await tester.tap(row);
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.text(en.contactsRemove));
      await pumpFrames(tester, frames: 6);
      expect(world.api.removedContacts, {'tom_walsh'});
      expect(findCopy(en.contactsRemoved('@tom_walsh')), findsOneWidget);
      expect(findCopy(en.contactsRemoved('tom_walsh')), findsNothing);
    });
    semantics.dispose();
  });
}
