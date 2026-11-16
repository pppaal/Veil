import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// What a group is called. The relay's conversation list names a group's
// members but not the group, so the app asks for each group once and keeps
// the answer across refreshes; until it has one, the group is called by
// its other members.

const group = 'conv-group';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeRelay relay;
  late MessengerParty alice;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    for (final handle in ['bob', 'carol']) {
      relay.addParty(RelayParty(
        handle: handle,
        userId: 'user-$handle',
        deviceId: 'dev-$handle',
        identity: alice.device.identity,
      ));
    }
    relay.addGroup(group, ['alice', 'bob', 'carol'], name: 'Moving day');
  });

  tearDown(() => alice.dispose());

  String? title() => switch (alice.controller.conversationById(group)) {
        final conversation? => conversationTitle(l10n, conversation, localUserId: 'user-alice'),
        null => null,
      };

  test('a group is called by its name, which is asked for once', () async {
    await alice.signIn();
    await waitFor(() => title() == 'Moving day', reason: 'the group was not named: ${title()}');

    await alice.controller.refreshConversations();
    await alice.restart();
    await waitFor(() => title() == 'Moving day', reason: 'the name was lost: ${title()}');
    await alice.controller.refreshConversations();
    expect(title(), 'Moving day', reason: 'a refresh keeps the name');
    expect(alice.api.groupFetches, {group: 2}, reason: 'once per start, not once per refresh');
  });

  test('until its name comes, a group is called by its other members, and the next refresh asks again', () async {
    alice.api.failGroupFetches = 1;
    await alice.signIn();
    await waitFor(() => title() != null, reason: 'the group was not listed');
    expect(title(), 'bob, carol', reason: 'the members the relay lists, without the user');

    await alice.controller.refreshConversations();
    expect(title(), 'Moving day');
    expect(alice.api.groupFetches, {group: 2});
  });
}
