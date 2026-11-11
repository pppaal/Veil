import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/reactions.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';

const conv = 'conv-1';

ChatMessage _message(String id) => ChatMessage(
      id: id,
      senderDeviceId: 'dev',
      sentAt: DateTime.utc(2026, 4, 1),
      envelope: const CryptoEnvelope(
        version: 'v',
        conversationId: conv,
        senderDeviceId: 'dev',
        recipientUserId: '',
        ciphertext: 'c',
        nonce: 'n',
        messageKind: MessageKind.text,
      ),
    );

ReactionPosition _at(int order) =>
    ReactionPosition(conversationOrder: order, sentAt: DateTime.utc(2026, 4, 1).add(Duration(minutes: order)));

void main() {
  group('controller', () {
    late FakeRelay relay;
    late VeilMessengerController atlas;
    late VeilMessengerController selene;

    setUp(() async {
      relay = FakeRelay();
      seedMockParties(relay, conv, ['atlas', 'selene']);
      atlas = mockPartyController(relay, 'atlas');
      selene = mockPartyController(relay, 'selene');
      addTearDown(atlas.dispose);
      addTearDown(selene.dispose);
      await atlas.applySession(mockPartySession('atlas'));
      await selene.applySession(mockPartySession('selene'));
      await selene.sendText(conversationId: conv, body: 'react to me');
      await waitFor(() => atlas.messagesFor(conv).length == 1);
    });

    test('toggleReaction sends messageType reaction with inner JSON and no REST call', () async {
      final target = atlas.messagesFor(conv).single;

      await atlas.toggleReaction(target, '🎉');
      await waitFor(() => relay.conversations[conv]!.messages.length == 2);

      // Applied locally at once.
      expect(atlas.messagesFor(conv).first.reactions.single.emoji, '🎉');
      // The relay got one more encrypted message, not a reaction call, and
      // cannot read either the target or the emoji.
      final relayed = relay.conversations[conv]!.messages.last;
      expect(relayed['messageType'], 'reaction');
      expect(jsonEncode(relayed), isNot(contains('🎉')));
      await waitFor(() => selene.messagesFor(conv).length == 2);
      final opened = await selene.decryptMessage(selene.messagesFor(conv).last);
      expect(opened.messageKind, MessageKind.reaction);
      expect(json.decode(opened.body), {'v': 1, 'target': target.id, 'emoji': '🎉', 'op': 'add'});
      await waitFor(() => selene.messagesFor(conv).first.reactions.isNotEmpty);
      expect(selene.messagesFor(conv).first.reactions.single.userId, 'user-atlas');

      // The same emoji again withdraws it, end to end too.
      await atlas.toggleReaction(atlas.messagesFor(conv).first, '🎉');
      await waitFor(() => selene.messagesFor(conv).first.reactions.isEmpty);
      expect(atlas.messagesFor(conv).first.reactions, isEmpty);
    });

    test('relay message.reaction events never change reactions', () async {
      final target = atlas.messagesFor(conv).single;
      await atlas.toggleReaction(target, '🎉');
      await waitFor(() => selene.messagesFor(conv).first.reactions.isNotEmpty);

      // A hostile relay withdraws atlas's authenticated reaction, swaps in
      // another, and puts words in selene's own mouth.
      final realtime = relay.realtimeFor('selene');
      realtime.deliver('message.reaction', {'messageId': target.id, 'userId': 'user-atlas', 'emoji': '🎉', 'action': 'remove'});
      realtime.deliver('message.reaction', {'messageId': target.id, 'userId': 'user-atlas', 'emoji': '💀', 'action': 'add'});
      realtime.deliver('message.reaction', {'messageId': target.id, 'userId': 'user-selene', 'emoji': '👎', 'action': 'add'});
      await settle();

      final reactions = selene.messagesFor(conv).first.reactions;
      expect(reactions, hasLength(1));
      expect(reactions.single.userId, 'user-atlas');
      expect(reactions.single.emoji, '🎉');
    });

    test('an oversized emoji is not sent', () async {
      await atlas.toggleReaction(atlas.messagesFor(conv).single, '👍👍👍👍👍👍👍👍👍');
      await settle();

      expect(relay.conversations[conv]!.messages, hasLength(1));
    });
  });

  group('ReactionPayload', () {
    test('refuses anything but a well-formed v1 reaction', () {
      expect(ReactionPayload.tryDecode('{"v":1,"target":"m","emoji":"🔥","op":"add"}')?.add, isTrue);
      for (final body in [
        'not json',
        '{"v":2,"target":"m","emoji":"🔥","op":"add"}',
        '{"v":1,"target":"","emoji":"🔥","op":"add"}',
        '{"v":1,"target":"m","emoji":"","op":"add"}',
        '{"v":1,"target":"m","emoji":"123456789","op":"add"}',
        '{"v":1,"target":"m","emoji":"🔥","op":"replace"}',
        '[1]',
      ]) {
        expect(ReactionPayload.tryDecode(body), isNull, reason: body);
      }
    });
  });

  group('ReactionLedger', () {
    test('the latest reaction of each reactor wins whatever the arrival order', () {
      final ledger = ReactionLedger();
      ledger.apply(conversationId: conv, target: 'm1', reactor: 'u1', emoji: '🔥', add: true, position: _at(5));
      final older = ledger.apply(conversationId: conv, target: 'm1', reactor: 'u1', emoji: '👍', add: true, position: _at(3));

      expect(older, isFalse);
      expect(ledger.emojiOf(conv, 'm1', 'u1'), '🔥');

      ledger.apply(conversationId: conv, target: 'm1', reactor: 'u1', emoji: '🔥', add: false, position: _at(6));
      expect(ledger.emojiOf(conv, 'm1', 'u1'), isNull);
    });

    test('reactions land only on targets in their own conversation', () {
      final ledger = ReactionLedger()
        ..apply(conversationId: 'other', target: 'm1', reactor: 'u1', emoji: '🔥', add: true, position: _at(1));

      expect(ledger.decorate(conv, [_message('m1')]).single.reactions, isEmpty);
      expect(ledger.decorate('other', [_message('m1')]).single.reactions.single.emoji, '🔥');
    });
  });
}
