import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_api_mapper.dart';

Map<String, dynamic> _messageJson([Map<String, dynamic> overrides = const {}]) => {
      'id': 'srv-1',
      'clientMessageId': 'client-1',
      'conversationId': 'conv-1',
      'senderDeviceId': 'dev-selene',
      'conversationOrder': 4,
      'ciphertext': 'ct',
      'nonce': 'n',
      'messageType': 'text',
      'expiresAt': null,
      'serverReceivedAt': '2026-04-01T12:00:00.000Z',
      'deliveredAt': null,
      'readAt': null,
      ...overrides,
    };

Map<String, dynamic> _conversationJson([Map<String, dynamic> overrides = const {}]) => {
      'id': 'conv-1',
      'type': 'direct',
      'createdAt': '2026-04-01T10:00:00.000Z',
      'members': [
        {'userId': 'user-atlas', 'handle': 'atlas', 'displayName': 'Atlas'},
        {'userId': 'user-selene', 'handle': 'selene', 'displayName': null},
      ],
      'lastMessage': null,
      'disappearingTimerSeconds': null,
      ...overrides,
    };

void main() {
  final mapper = MessengerApiMapper(createDefaultCryptoAdapter().envelopeCodec);

  group('messages', () {
    test('a well-formed message maps with its receipts and owner', () {
      final message = mapper.message(
        _messageJson({'readAt': '2026-04-01T12:05:00.000Z', 'deliveredAt': '2026-04-01T12:01:00.000Z'}),
        localDeviceId: 'dev-selene',
      )!;

      expect(message.id, 'srv-1');
      expect(message.conversationOrder, 4);
      expect(message.deliveryState, MessageDeliveryState.read);
      expect(message.isMine, isTrue);
      expect(message.envelope.conversationId, 'conv-1');
    });

    const malformed = <String, Object?>{
      'not a map': 'srv-1',
      'null': null,
      'a list': ['srv-1'],
    };
    for (final MapEntry(key: label, value: raw) in malformed.entries) {
      test('malformed JSON ($label) reads as null', () {
        expect(mapper.message(raw, localDeviceId: 'dev-atlas'), isNull);
      });
    }

    final badFields = <String, Map<String, dynamic>>{
      'missing id': {'id': null},
      'id of the wrong type': {'id': 7},
      'unparseable receipt time': {'serverReceivedAt': 'yesterday'},
      'delivered time of the wrong type': {'deliveredAt': 12},
      'unparseable expiry': {'expiresAt': 'soon'},
      'order as a string': {'conversationOrder': '4'},
      'client id of the wrong type': {'clientMessageId': 3},
    };
    for (final MapEntry(key: label, value: overrides) in badFields.entries) {
      test('malformed JSON ($label) reads as null', () {
        expect(mapper.message(_messageJson(overrides), localDeviceId: 'dev-atlas'), isNull);
      });
    }

    test('a page keeps the well-formed items and its cursor', () {
      final page = mapper.messagePage(
        {
          'items': [_messageJson(), 'garbage', _messageJson({'id': 'srv-2', 'serverReceivedAt': 'never'})],
          'nextCursor': 'cursor-2',
        },
        localDeviceId: 'dev-atlas',
      );

      expect(page.items.map((message) => message.id), ['srv-1']);
      expect(page.nextCursor, 'cursor-2');
    });

    test('a page without items or with a malformed cursor is empty and final', () {
      final page = mapper.messagePage({'items': 'nope', 'nextCursor': 5}, localDeviceId: null);

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('conversations', () {
    test('a 1:1 names the member that is not this user, with an empty bundle', () {
      final conversation = mapper.conversation(_conversationJson(), localHandle: 'atlas')!;

      expect(conversation.peerHandle, 'selene');
      expect(conversation.recipientBundle.userId, 'user-selene');
      expect(conversation.recipientBundle.identityPublicKey, isEmpty);
      expect(conversation.members, isEmpty);
      expect(conversation.updatedAt, DateTime.parse('2026-04-01T10:00:00.000Z'));
    });

    test('a group carries its members, Sender Keys flag and epoch', () {
      final conversation = mapper.conversation(
        _conversationJson({'type': 'group', 'useSenderKeys': true, 'currentEpoch': 3}),
        localHandle: 'atlas',
      )!;

      expect(conversation.type, ConversationType.group);
      expect(conversation.members.map((member) => member.handle), ['atlas', 'selene']);
      expect(conversation.useSenderKeys, isTrue);
      expect(conversation.groupEpoch, 3);
    });

    final badFields = <String, Map<String, dynamic>>{
      'no members': {'members': <Object?>[]},
      'members not a list': {'members': 'atlas,selene'},
      'member without a handle': {
        'members': [
          {'userId': 'user-selene'},
        ],
      },
      'unparseable creation time': {'createdAt': 'today'},
      'timer as a string': {'disappearingTimerSeconds': '30'},
      'last message that is not one': {'lastMessage': 'hello'},
    };
    for (final MapEntry(key: label, value: overrides) in badFields.entries) {
      test('malformed JSON ($label) reads as null', () {
        expect(mapper.conversation(_conversationJson(overrides), localHandle: 'atlas'), isNull);
      });
    }

    test('the list keeps the well-formed conversations', () {
      final conversations = mapper.conversations(
        {
          'items': [_conversationJson(), 42, _conversationJson({'id': 'conv-2', 'members': null})],
        },
        localHandle: 'atlas',
      );

      expect(conversations.map((conversation) => conversation.id), ['conv-1']);
    });
  });

  group('tickets and echoes', () {
    test('an upload ticket needs every field it is used for', () {
      final ticket = mapper.uploadTicket({
        'attachmentId': 'att-1',
        'upload': {
          'storageKey': 'blob/att-1',
          'uploadUrl': 'https://relay.invalid/upload',
          'expiresAt': '2026-04-01T13:00:00.000Z',
          'headers': {'x-size': 12},
        },
      })!;

      expect(ticket.attachmentId, 'att-1');
      expect(ticket.headers, {'x-size': '12'});
      expect(mapper.uploadTicket({'attachmentId': 'att-1', 'upload': 'later'}), isNull);
      expect(
        mapper.uploadTicket({
          'attachmentId': 'att-1',
          'upload': {'storageKey': 'k', 'uploadUrl': 'u', 'expiresAt': 'whenever'},
        }),
        isNull,
      );
    });

    test('a download ticket and a created conversation read their one field', () {
      expect(mapper.downloadUrl({'ticket': {'downloadUrl': 'https://relay.invalid/d'}}), 'https://relay.invalid/d');
      expect(mapper.downloadUrl({'ticket': null}), isNull);
      expect(mapper.createdConversationId({'conversation': {'id': 'conv-9'}}), 'conv-9');
      expect(mapper.createdConversationId({'conversation': []}), isNull);
    });

    test('the timer echo falls back to the request and refuses a malformed timer', () {
      expect(mapper.appliedTimer({}, requested: 30)?.seconds, 30);
      expect(mapper.appliedTimer({'conversation': {'disappearingTimerSeconds': 60}}, requested: 30)?.seconds, 60);
      expect(mapper.appliedTimer({'conversation': <String, dynamic>{}}, requested: 30)?.seconds, isNull);
      expect(mapper.appliedTimer({'conversation': {'disappearingTimerSeconds': '60'}}, requested: 30), isNull);
    });
  });
}
