import '../../../../core/identity/trusted_identity_resolver.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../conversation_models.dart';

const _migratedMarkerKey = 'legacy_trust_migrated.v1';

/// Carries what earlier builds knew about contact identities into the pin
/// table, once, so upgrading does not reopen trust on first use for
/// contacts this device already talks to. It must finish before the first
/// trust decision (see IdentityTrust's `ready`): a handshake or directory
/// answer evaluated earlier would be pinned on first use instead.
///
/// For each direct conversation, on the device its session talks to (or the
/// cached bundle's device when it has none):
/// - a safety-number verification is pinned as verified at its date, unless
///   the session recorded a different key, which makes the verification
///   stale; sessions from before keys were recorded rely on the verified key,
///   and if the peer actually uses another, the next handshake or directory
///   answer presenting it meets a verified pin and is held back for
///   re-verification;
/// - otherwise the key the session recorded is pinned unverified.
/// Verifications of group members named no device and cannot be placed; they
/// are dropped and the screen offers to verify again. The old records are
/// deleted once read.
Future<void> migrateLegacyTrust({
  required SecureStorageService storage,
  required TrustedIdentityResolver resolver,
  required Future<List<ConversationPreview>> Function() readConversations,
}) async {
  final marker = storage.scoped(SecureScope.identity);
  if (await marker.read(_migratedMarkerKey) != null) return;
  final verifications = await storage.readAllSafetyVerifications();
  for (final conversation in await readConversations()) {
    final userId = conversation.recipientBundle.userId;
    if (conversation.type != ConversationType.direct || userId.isEmpty) continue;
    final session = conversation.sessionState;
    final sessionKey = session?.remoteIdentityPublicKey ?? '';
    final deviceId = switch (session?.remoteDeviceId) {
      final String id when id.isNotEmpty => id,
      _ => conversation.recipientBundle.deviceId,
    };
    if (deviceId.isEmpty) continue;
    final verification = verifications[conversation.id];
    try {
      if (verification != null && (sessionKey.isEmpty || sessionKey == verification.peerIdentityPublicKey)) {
        await resolver.adoptVerified(userId, deviceId, verification.peerIdentityPublicKey,
            verifiedAt: verification.verifiedAt);
      } else if (sessionKey.isNotEmpty) {
        await resolver.evaluate(userId, deviceId, sessionKey);
      }
    } on ArgumentError {
      // A key that does not decode names no identity; there is nothing to
      // carry over, and one bad record must not hold back every decision.
    }
  }
  await storage.clearAllSafetyVerifications();
  await marker.write(_migratedMarkerKey, DateTime.now().toUtc().toIso8601String());
}
