import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/local_notice.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_merge.dart';

const conv = 'conv-1';

void main() {
  final raisedAt = DateTime.utc(2026, 11, 1, 9);
  const event = NewDeviceAdmitted(conv, userId: 'user-selene', deviceId: 'dev-selene-2');

  ChatMessage relayed(int order) => ChatMessage(
        id: 'msg-$order',
        senderDeviceId: 'dev-selene',
        sentAt: raisedAt.subtract(Duration(minutes: 3 - order)),
        conversationOrder: order,
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v2',
          conversationId: conv,
          senderDeviceId: 'dev-selene',
          recipientUserId: 'user-atlas',
          ciphertext: 'ct',
          nonce: 'n',
          messageKind: MessageKind.text,
        ),
      );

  List<String> sortedIds(List<ChatMessage> messages) => [for (final m in List.of(messages)..sort(compareMessages)) m.id];

  test('a notice sorts right after the newest message it was raised against', () {
    final earlier = [relayed(1), relayed(2)];
    final notice = localNoticeFor(event, conversationMessages: earlier, now: raisedAt)!.message;

    expect(sortedIds([relayed(3), notice, ...earlier]), ['msg-1', 'msg-2', notice.id, 'msg-3']);
  });

  test('a notice raised before any message sorts ahead of later ones', () {
    final notice = localNoticeFor(event, conversationMessages: const [], now: raisedAt)!.message;

    expect(sortedIds([relayed(1), notice]), [notice.id, 'msg-1']);
  });
}
