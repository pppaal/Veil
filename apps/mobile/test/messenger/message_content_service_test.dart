import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_content_service.dart';

import '../support/strict_mock_crypto_adapter.dart';

const _conversationId = 'conv-1';

const _outerAttachment = AttachmentReference(
  attachmentId: 'att-outer',
  storageKey: 'attachments/att-outer/blob',
  contentType: 'application/pdf',
  sizeBytes: 10,
  sha256: 'outer',
  encryptedKey: 'outer-key',
  nonce: 'outer-nonce',
);

CryptoEnvelope _envelope(String ciphertext, {AttachmentReference? attachment}) => CryptoEnvelope(
      version: 'veil-envelope-v1',
      conversationId: _conversationId,
      senderDeviceId: 'dev-peer',
      recipientUserId: 'user-local',
      ciphertext: ciphertext,
      nonce: 'nonce-$ciphertext',
      messageKind: MessageKind.system,
      expiresAt: DateTime.utc(2030),
      attachment: attachment,
    );

ChatMessage _message(
  String id,
  CryptoEnvelope envelope, {
  String? clientMessageId,
  bool isMine = false,
}) {
  return ChatMessage(
    id: id,
    clientMessageId: clientMessageId,
    senderDeviceId: isMine ? 'dev-local' : 'dev-peer',
    sentAt: DateTime.utc(2026, 4, 1),
    envelope: envelope,
    isMine: isMine,
  );
}

/// Decrypter that answers from a script and counts calls.
class _ScriptedDecrypter {
  _ScriptedDecrypter(this.answers);

  final List<DecryptedMessage Function(CryptoEnvelope envelope)> answers;
  int calls = 0;

  Future<DecryptedMessage> call(CryptoEnvelope envelope) async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls += 1;
    return answer(envelope);
  }
}

DecryptedMessage Function(CryptoEnvelope) _plain(String body, {AttachmentReference? attachment}) =>
    (_) => DecryptedMessage(body: body, messageKind: MessageKind.text, attachment: attachment);

DecryptedMessage Function(CryptoEnvelope) _placeholder(String body) => (envelope) => DecryptedMessage(
      body: body,
      messageKind: envelope.messageKind,
      expiresAt: envelope.expiresAt,
      attachment: envelope.attachment,
    );

MessageContentService _service(
  Future<DecryptedMessage> Function(CryptoEnvelope) decrypt, {
  ConversationCacheService? cache,
  List<MessageContentRecord>? stored,
}) {
  return MessageContentService(
    cache: cache,
    decrypt: decrypt,
    onContentStored: (_, record) => stored?.add(record),
  );
}

void main() {
  test('a frame is decrypted once; later reads come from memory or the store', () async {
    final peer = StrictMockCryptoAdapter();
    final local = StrictMockCryptoAdapter();
    var decrypts = 0;
    Future<DecryptedMessage> decrypt(CryptoEnvelope envelope) {
      decrypts += 1;
      return local.messaging.decryptMessage(envelope);
    }

    final envelope = await peer.messaging.encryptMessage(
      conversationId: _conversationId,
      senderDeviceId: 'dev-peer',
      recipientUserId: 'user-local',
      body: 'hello',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-local',
        deviceId: 'dev-local',
        handle: 'local',
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final message = _message('srv-1', envelope);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftConversationCacheService(database, envelopeCodec: local.envelopeCodec);

    final service = _service(decrypt, cache: cache);
    final first = service.read(message);
    expect(identical(service.read(message), first), isTrue);
    await service.ingestAll([message]);
    expect((await first).body, 'hello');

    // A fresh service over the same database is what a restart looks like.
    final restarted = _service(decrypt, cache: cache);
    expect((await restarted.read(message)).body, 'hello');
    expect(decrypts, 1);
  });

  test('own messages are shown from stored plaintext and never decrypted', () async {
    final decrypter = _ScriptedDecrypter([_placeholder('[Decryption failed]')]);
    final service = _service(decrypter.call);
    final envelope = _envelope('own-1');

    await service.storeOutbound(
      conversationId: _conversationId,
      clientMessageId: 'client-1',
      body: 'my words',
      kind: MessageKind.text,
    );
    final echo = _message('local-client-1', envelope, clientMessageId: 'client-1', isMine: true);
    expect((await service.read(echo)).body, 'my words');

    await service.acknowledge(clientMessageId: 'client-1', serverMessageId: 'srv-1');
    final acked = _message('srv-1', envelope, clientMessageId: 'client-1', isMine: true);
    expect((await service.read(acked)).body, 'my words');

    // The relay's copy can arrive before the ack moves the content.
    await service.storeOutbound(
      conversationId: _conversationId,
      clientMessageId: 'client-2',
      body: 'raced the ack',
      kind: MessageKind.text,
    );
    final early = _message('srv-2', _envelope('own-2'), clientMessageId: 'client-2', isMine: true);
    expect((await service.read(early)).body, 'raced the ack');
    expect(decrypter.calls, 0);
  });

  test('only rows waiting for key material are retried', () async {
    final decrypter = _ScriptedDecrypter([
      _placeholder('[Awaiting sender key — sync required]'),
      _plain('finally readable'),
    ]);
    final failing = _ScriptedDecrypter([_placeholder('[Decryption failed]'), _plain('never')]);
    final service = _service(decrypter.call);
    final failingService = _service(failing.call);
    final waiting = _message('srv-1', _envelope('frame-1'));
    final broken = _message('srv-2', _envelope('frame-2'));

    expect((await service.read(waiting)).body, '[Awaiting sender key — sync required]');
    expect((await service.read(waiting)).body, '[Awaiting sender key — sync required]');
    expect(decrypter.calls, 1);

    await service.retryPending(_conversationId, [waiting]);
    expect((await service.read(waiting)).body, 'finally readable');
    await service.retryPending(_conversationId, [waiting]);
    expect(decrypter.calls, 2);

    await failingService.read(broken);
    await failingService.retryPending(_conversationId, [broken]);
    expect((await failingService.read(broken)).body, '[Decryption failed]');
    expect(failing.calls, 1);
  });

  test('placeholders never carry kind, expiry or attachment from the envelope', () async {
    final stored = <MessageContentRecord>[];
    final service = _service(
      _ScriptedDecrypter([_placeholder('[Decryption failed]')]).call,
      stored: stored,
    );

    final shown = await service.read(
      _message('srv-1', _envelope('frame-1', attachment: _outerAttachment)),
    );

    expect(shown.messageKind, MessageKind.text);
    expect(shown.expiresAt, isNull);
    expect(shown.attachment, isNull);
    expect(stored.single.status, MessageContentStatus.failed);
  });

  test('attachment metadata is taken only from the inner payload', () async {
    const inner = AttachmentReference(
      attachmentId: 'att-inner',
      storageKey: 'attachments/att-inner/blob',
      contentType: 'image/png',
      sizeBytes: 20,
      sha256: 'inner',
      encryptedKey: 'inner-key',
      nonce: 'inner-nonce',
    );
    final service = _service(_ScriptedDecrypter([
      (envelope) => DecryptedMessage(
            body: 'outer echoed',
            messageKind: MessageKind.file,
            attachment: envelope.attachment,
          ),
      _plain('inner carried', attachment: inner),
    ]).call);

    final echoed = await service.read(_message('srv-1', _envelope('f1', attachment: _outerAttachment)));
    final carried = await service.read(_message('srv-2', _envelope('f2', attachment: _outerAttachment)));

    expect(echoed.attachment, isNull);
    expect(carried.attachment!.attachmentId, 'att-inner');
  });

  test('outbound text that never reached the outbox is discarded', () async {
    final service = _service(_ScriptedDecrypter([_plain('unused')]).call);
    final echo = _message('local-client-9', _envelope('x'), clientMessageId: 'client-9', isMine: true);

    await service.storeOutbound(
      conversationId: _conversationId,
      clientMessageId: 'client-9',
      body: 'never sent',
      kind: MessageKind.text,
    );
    await service.discardOutbound('client-9');

    expect(await service.storedFor([echo]), isEmpty);
  });

  test('our own content comes back with its sealed expiry when the relay copy binds to it', () async {
    final inner = DateTime.utc(2030, 1, 1, 12);
    final bound = <MessageContentRecord>[];
    final service = _service(_ScriptedDecrypter([_plain('unused')]).call, stored: bound);
    for (final clientMessageId in ['client-ack', 'client-echo']) {
      await service.storeOutbound(
        conversationId: _conversationId,
        clientMessageId: clientMessageId,
        body: 'timed',
        kind: MessageKind.text,
        expiresAt: inner,
      );
    }

    final acked = await service.acknowledge(clientMessageId: 'client-ack', serverMessageId: 'srv-ack');
    expect(acked!.innerExpiresAt, inner);

    // The relay's copy arrived first: the listener applies the expiry.
    await service.read(_message('srv-echo', _envelope('own'), clientMessageId: 'client-echo', isMine: true));
    expect(bound.single.messageKey, 'srv-echo');
    expect(bound.single.innerExpiresAt, inner);
  });

  test('messages this device expired are never served back or decrypted again', () async {
    final decrypter = _ScriptedDecrypter([_plain('once')]);
    final service = _service(decrypter.call);
    final message = _message('srv-gone', _envelope('gone'));
    final other = _message('srv-live', _envelope('live'));
    await service.ingestAll([message]);

    await service.deleteExpired(DateTime.now(), [message]);

    expect(await service.withoutRetired([message, other]), [other]);
    expect(decrypter.calls, 1);
  });
}
