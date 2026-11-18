import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/decrypted_message_cache.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_content_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';

// What the Chats row quotes for a file (spec D53): its name, sanitized as a
// file card shows it, so an override character cannot turn "exe" into
// "pdf" on the list either; nothing for a file with no name (the row then
// says "File").

const _conversation = 'conv-1';

void main() {
  late MessengerStateStore store;
  late MessageContentService contents;
  late DecryptedMessageCache latest;

  setUp(() {
    store = MessengerStateStore(onChanged: () {});
    contents = MessageContentService(
      cache: null,
      decrypt: (envelope, {beforeCommit}) => throw StateError('nothing is decrypted here'),
      onContentStored: (_, __) {},
    );
    latest = DecryptedMessageCache(contents: contents, store: store);
  });

  Future<String?> bodyOfLast(String clientMessageId, {required String body, required MessageKind kind}) async {
    await contents.storeOutbound(
      conversationId: _conversation,
      clientMessageId: clientMessageId,
      senderDeviceId: 'dev-atlas',
      body: body,
      kind: kind,
    );
    store.setMessages(_conversation, [
      ChatMessage(
        id: 'local-$clientMessageId',
        clientMessageId: clientMessageId,
        senderDeviceId: 'dev-atlas',
        sentAt: DateTime.utc(2026, 4, 7, 10),
        isMine: true,
        envelope: CryptoEnvelope(
          version: 'veil-envelope-v2',
          conversationId: _conversation,
          senderDeviceId: 'dev-atlas',
          recipientUserId: 'user-selene',
          ciphertext: '',
          nonce: '',
          messageKind: kind,
        ),
      ),
    ]);
    await latest.refresh(_conversation);
    return latest.bodyFor(_conversation);
  }

  test('a file is quoted by its sanitized name', () async {
    expect(await bodyOfLast('c1', body: 'lease.pdf', kind: MessageKind.file), 'lease.pdf');
    expect(await bodyOfLast('c2', body: 'invoice‮fdp.exe', kind: MessageKind.file), 'invoicefdp.exe');
    expect(latest.kindFor(_conversation), MessageKind.file);
    expect(latest.previewFor(_conversation), isNull, reason: 'only text is quoted as text');
  });

  test('a file with no name, or only characters the sanitizer drops, is not quoted', () async {
    expect(await bodyOfLast('c1', body: '', kind: MessageKind.file), isNull);
    expect(await bodyOfLast('c2', body: ' ‎‮ ', kind: MessageKind.file), isNull);
  });

  test('text and system lines are quoted as before, a photo is not', () async {
    expect(await bodyOfLast('c1', body: 'see you', kind: MessageKind.text), 'see you');
    expect(await bodyOfLast('c2', body: '@sam took a screenshot', kind: MessageKind.system), '@sam took a screenshot');
    expect(await bodyOfLast('c3', body: '', kind: MessageKind.image), isNull);
  });
}
