import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';
import 'identity_trust.dart';

/// Codes of the notices this device writes into a conversation itself. The
/// chat renders them by code, and only on rows whose id marks them local, so
/// a peer that sends the same words as a system message gets plain text.
abstract final class LocalNoticeCodes {
  static const identityChanged = 'identity.changed';
  static const identityNewDevice = 'identity.new_device';
}

/// A notice row and the code it shows.
class LocalNotice {
  const LocalNotice(this.message, this.code);

  final ChatMessage message;
  final String code;
}

/// The notice [event] calls for, or null when it calls for none. Its id is
/// derived from what it announces, so announcing the same change again, in
/// this run or after a restart, finds the row already there.
LocalNotice? localNoticeFor(
  IdentityTrustEvent event, {
  required List<ChatMessage> conversationMessages,
  required DateTime now,
}) {
  final (String? code, String subject) = switch (event) {
    IdentityChangePending(:final change) => (
        LocalNoticeCodes.identityChanged,
        '${change.userId}:${change.deviceId}:${change.presentedKey}',
      ),
    NewDeviceAdmitted(:final userId, :final deviceId) => (LocalNoticeCodes.identityNewDevice, '$userId:$deviceId'),
    IdentityChangeResolved() => (null, ''),
  };
  if (code == null) return null;
  final latestOrder = conversationMessages.map((message) => message.conversationOrder).nonNulls.lastOrNull;
  return LocalNotice(
    ChatMessage(
      id: '$localNoticeIdPrefix$code:${event.conversationId}:$subject',
      senderDeviceId: '',
      sentAt: now,
      // Sorts right after the newest relayed message it was raised against,
      // or ahead of every message in a conversation that has none yet.
      conversationOrder: latestOrder ?? 0,
      envelope: CryptoEnvelope(
        version: '',
        conversationId: event.conversationId,
        senderDeviceId: '',
        recipientUserId: '',
        ciphertext: '',
        nonce: '',
        messageKind: MessageKind.system,
      ),
    ),
    code,
  );
}
