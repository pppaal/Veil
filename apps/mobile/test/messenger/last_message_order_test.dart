import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_merge.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_api_mapper.dart';

// The order of the last message a conversation list names
// (lastMessage.conversationOrder), which the first list on a new device
// reads every conversation through: the mapper reads it, and the merge
// keeps it, from the relay's copy and for a 1:1 bound to its peer.

Map<String, dynamic> _lastMessage(Object? order) => {
      'id': 'srv-9',
      'conversationId': 'conv-1',
      'senderDeviceId': 'dev-selene',
      if (order != _absent) 'conversationOrder': order,
      'ciphertext': 'ct',
      'nonce': 'n',
      'messageType': 'text',
      'serverReceivedAt': '2026-04-01T12:00:00.000Z',
    };

const _absent = Object();

Map<String, dynamic> _conversation({Object? lastMessage}) => {
      'id': 'conv-1',
      'type': 'direct',
      'createdAt': '2026-04-01T10:00:00.000Z',
      'members': [
        {'userId': 'user-atlas', 'handle': 'atlas'},
        {'userId': 'user-selene', 'handle': 'selene'},
      ],
      'lastMessage': lastMessage,
    };

ConversationPreview _preview({int? order, String userId = 'user-selene', ConversationSessionState? session}) =>
    ConversationPreview(
      id: 'conv-1',
      peerHandle: 'selene',
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: userId,
        deviceId: '',
        handle: 'selene',
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      lastMessageOrder: order,
      updatedAt: DateTime.utc(2026, 4, 1),
      sessionState: session,
    );

void main() {
  final mapper = MessengerApiMapper(createDefaultCryptoAdapter().envelopeCodec);
  ConversationPreview? map(Map<String, dynamic> raw) => mapper.conversation(raw, localHandle: 'atlas', localUserId: 'user-atlas');

  group('the mapper', () {
    test('reads the last message\'s order', () {
      expect(map(_conversation(lastMessage: _lastMessage(42)))!.lastMessageOrder, 42);
    });

    test('reads none when the list names no last message, or the message carries no order', () {
      expect(map(_conversation())!.lastMessageOrder, isNull);
      expect(map(_conversation(lastMessage: _lastMessage(_absent)))!.lastMessageOrder, isNull);
      expect(map(_conversation(lastMessage: _lastMessage(null)))!.lastMessageOrder, isNull);
    });

    for (final malformed in <Object>['42', 4.2, true, <int>[42]]) {
      test('drops the conversation for a malformed order ($malformed), as for any malformed field', () {
        expect(map(_conversation(lastMessage: _lastMessage(malformed))), isNull);
        expect(
          mapper.conversations({
            'items': [_conversation(lastMessage: _lastMessage(malformed))],
          }, localHandle: 'atlas', localUserId: 'user-atlas'),
          isEmpty,
        );
      });
    }
  });

  group('the merge', () {
    test('takes the relay\'s order over the local one', () {
      final merged = mergeConversationPreviews([_preview(order: 3)], [_preview(order: 8)]).single;
      expect(merged.lastMessageOrder, 8);
    });

    test('keeps the order a new list leaves out as none, as the relay says', () {
      final merged = mergeConversationPreviews([_preview(order: 3)], [_preview()]).single;
      expect(merged.lastMessageOrder, isNull);
    });

    test('copies the order with the last message onto a 1:1 bound to its peer', () {
      const bound = ConversationPeer(userId: 'user-selene', handle: 'selene');
      // The relay names another account; the bound peer stays, the last
      // message and its order move.
      final merged = mergeConversationPreviews(
        [_preview(order: 3)],
        [_preview(order: 11, userId: 'user-other')],
        bound: {'conv-1': bound},
      ).single;
      expect(merged.recipientBundle.userId, 'user-selene');
      expect(merged.lastMessageOrder, 11);

      // With no local preview left, the bound one is rebuilt with it too.
      final rebuilt = mergeConversationPreviews(
        const [],
        [_preview(order: 12, userId: 'user-other')],
        bound: {'conv-1': bound},
      ).single;
      expect(rebuilt.recipientBundle.userId, 'user-selene');
      expect(rebuilt.lastMessageOrder, 12);
    });

    test('copyWith keeps or clears the order', () {
      final preview = _preview(order: 5);
      expect(preview.copyWith(peerHandle: 'x').lastMessageOrder, 5);
      expect(preview.copyWith(lastMessageOrder: null).lastMessageOrder, isNull);
    });
  });
}
