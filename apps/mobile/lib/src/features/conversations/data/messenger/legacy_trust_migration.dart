import '../../../../core/identity/trusted_identity_resolver.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../conversation_models.dart';

const _migratedMarkerKey = 'legacy_trust_migrated.v1';

/// Carries what earlier builds knew about contact identities into the pin
/// table, once, so upgrading does not reopen trust on first use for
/// contacts this device already talks to.
///
/// Each direct session recorded the identity key it was opened to; that key
/// is pinned for its device unless a pin already decides that device. A
/// safety-number verification of exactly that key keeps its date as the
/// pin's verifiedAt. Verifications of group members named no device and
/// cannot be placed; they are dropped and the screen offers to verify again.
/// The old records are deleted once read.
Future<void> migrateLegacyTrust({
  required SecureStorageService storage,
  required TrustedIdentityResolver resolver,
  required List<ConversationPreview> conversations,
}) async {
  final marker = storage.scoped(SecureScope.identity);
  if (await marker.read(_migratedMarkerKey) != null) return;
  final verifications = await storage.readAllSafetyVerifications();
  for (final conversation in conversations) {
    final session = conversation.sessionState;
    final userId = conversation.recipientBundle.userId;
    if (conversation.type != ConversationType.direct || session == null || userId.isEmpty) continue;
    final key = session.remoteIdentityPublicKey;
    final deviceId = session.remoteDeviceId;
    if (key.isEmpty || deviceId.isEmpty) continue;
    final verification = verifications[conversation.id];
    if (verification != null && verification.peerIdentityPublicKey == key) {
      await resolver.adoptVerified(userId, deviceId, key, verifiedAt: verification.verifiedAt);
    } else {
      await resolver.evaluate(userId, deviceId, key);
    }
  }
  await storage.clearAllSafetyVerifications();
  await marker.write(_migratedMarkerKey, DateTime.now().toUtc().toIso8601String());
}
