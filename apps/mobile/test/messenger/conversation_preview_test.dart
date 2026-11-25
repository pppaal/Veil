import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_labels.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// What a row of the conversation list says under the name, for real
// controllers with real ratchets over the fake relay. The row's words come
// from conversationPreviewLine, which is what both list layouts draw.

const conv = 'conv-ab';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  String row(MessengerParty party, [String conversationId = conv]) =>
      conversationPreviewLine(l10n, party.controller.conversationById(conversationId)!, party.controller);

  Future<void> send(MessengerParty from, String body, {String conversationId = conv, Duration? disappearAfter}) async {
    await from.controller.sendText(conversationId: conversationId, body: body, disappearAfter: disappearAfter);
    await waitFor(() => from.controller.pendingCountFor(conversationId) == 0, reason: '"$body" was not acked');
  }

  test('a message that arrives while the list is open is previewed with its text, and again after a restart',
      () async {
    await alice.signIn();
    await bob.signIn();
    expect(row(alice), 'No messages yet');

    // Alice never opens the chat: no loadConversationMessages, no active
    // conversation. The frame reaches her over the socket.
    await send(bob, 'dinner at eight?');
    await waitFor(() => row(alice) == 'dinner at eight?', reason: 'the live message was not previewed: ${row(alice)}');
    expect(alice.api.markReadCalls, isEmpty, reason: 'previewing a message does not mark it read');

    await alice.restart();
    await waitFor(() => row(alice) == 'dinner at eight?',
        reason: 'the preview did not come back after a restart: ${row(alice)}');
  });

  test('a message that arrived while the app was closed is previewed with its text once the list is back', () async {
    await bob.signIn();
    await send(bob, 'left the keys with the neighbour');

    // Alice was offline: she signs in to a list whose last message she has
    // never held.
    await alice.signIn();
    await waitFor(() => row(alice) == 'left the keys with the neighbour',
        reason: 'the message that waited on the relay was not previewed: ${row(alice)}');
    expect(alice.api.markReadCalls, isEmpty, reason: 'previewing a message does not mark it read');
    expect(alice.notifications.shownForConversations, isEmpty, reason: 'history that is fetched raises no notification');

    // It was read from the relay once and opened once: the restart shows it
    // from the local store.
    await alice.restart();
    await waitFor(() => row(alice) == 'left the keys with the neighbour',
        reason: 'the preview did not come back after a restart: ${row(alice)}');
  });

  test('a message that arrived while the app was closed, in a chat this device already holds, is previewed too',
      () async {
    await alice.signIn();
    await bob.signIn();
    await send(bob, 'first, while she is here');
    await waitFor(() => row(alice) == 'first, while she is here', reason: 'the live message: ${row(alice)}');

    // The app is closed; the relay keeps what arrives for it.
    await alice.restart(whileClosed: () => send(bob, 'second, while she is away'));
    await waitFor(() => row(alice) == 'second, while she is away',
        reason: 'the message that waited on the relay was not previewed: ${row(alice)}');
    expect(alice.api.markReadCalls, isEmpty, reason: 'previewing a message does not mark it read');
    expect(alice.controller.activeConversationId, isNull, reason: 'no chat was opened for it');
  });

  test('a group message that arrived while the app was closed is previewed too', () async {
    final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    addTearDown(carol.dispose);
    relay.addGroup('conv-group', ['alice', 'bob', 'carol']);
    await bob.signIn();
    await carol.signIn();
    await send(bob, 'movers come at nine', conversationId: 'conv-group');

    await alice.signIn();
    await waitFor(() => row(alice, 'conv-group') == 'movers come at nine',
        reason: 'the group message was not previewed: ${row(alice, 'conv-group')}');
  });

  test('a disappearing message is previewed only until it expires, and not after a restart', () async {
    await alice.signIn();
    await bob.signIn();
    await send(bob, 'see you there');
    // Long enough to be seen on a busy machine before it goes.
    await send(bob, 'door code 4471', disappearAfter: const Duration(seconds: 5));
    await waitFor(() => row(alice) == 'door code 4471', reason: 'not previewed while it lives: ${row(alice)}');
    expect(
      conversationExpiryLabel(l10n, alice.controller.conversationById(conv)!, alice.controller),
      startsWith('Expires in'),
      reason: 'the row says the message disappears',
    );

    // From its expiry until the sweep timer drops it, the row reads "Message
    // expired"; on a busy machine the poll can run in that turn, before the
    // sweep that is already due, so wait for the fallback itself.
    await waitFor(() => row(alice) == 'see you there',
        timeout: const Duration(seconds: 12),
        reason: 'the row did not fall back to the message before it: ${row(alice)}');

    // The relay of this test never sweeps, and still lists the expired
    // message as the conversation's last.
    await alice.restart();
    await settle();
    expect(row(alice), isNot(contains('4471')));
  });

  test('what this device cannot open is never quoted', () async {
    await bob.signIn();
    await send(bob, 'for the first device only');
    // The same account on a device that holds none of the first one's keys:
    // the frame was not sealed for it.
    final replacement = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice-2');
    addTearDown(replacement.dispose);
    await replacement.signIn();
    await settle();

    expect(row(replacement), 'Message');
    expect(replacement.controller.lastMessagePreviewFor(conv), isNull);
  });
}
