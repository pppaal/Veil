import '../../../../core/storage/conversation_cache_service.dart';

// TODO(wave 2: DecryptedMessage.status): the adapters and the group
// coordinator still report decrypt failures as placeholder bodies, so the
// status is recovered from the exact strings they emit today. Replace this
// table with the typed status once it lands.
const Map<String, MessageContentStatus> decryptPlaceholderStatuses = {
  '[Unable to decrypt: invalid envelope]': MessageContentStatus.failed,
  '[Decryption failed]': MessageContentStatus.failed,
  '[Identity changed — verify safety number]': MessageContentStatus.failed,
  '[Message from a previous group epoch]': MessageContentStatus.failed,
  '[Replayed or out-of-window message]': MessageContentStatus.replayed,
  '[Awaiting sender key — sync required]': MessageContentStatus.awaitingKey,
  '[Session not established — sync required]': MessageContentStatus.sessionMissing,
  // Nothing was consumed when the native bridge is down, so the frame can be
  // retried like a missing session.
  '[Crypto bridge unavailable]': MessageContentStatus.sessionMissing,
};

MessageContentStatus classifyDecryptOutcome(String body) =>
    decryptPlaceholderStatuses[body] ?? MessageContentStatus.ok;
