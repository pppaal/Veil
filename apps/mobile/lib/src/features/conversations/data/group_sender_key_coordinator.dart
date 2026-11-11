import 'dart:convert';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/group_sender_keys.dart';
import '../../../core/crypto/message_padding.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/util/keyed_async_lock.dart';
import 'conversation_models.dart';

/// Decides whether a directory identity may take part in Sender Keys: whether
/// we seal our chain key to it, and whether we accept a chain it signed.
typedef GroupIdentityTrustCheck = Future<bool> Function(
  String userId,
  String deviceId,
  String identityPublicKey,
);

/// Glue between the pure [GroupSenderKeyEngine] and the app: decides when we
/// need a fresh chain, fans our chain key out to the other members through
/// the server relay, picks up members' chain keys addressed to us, and turns
/// group frames into the same [CryptoEnvelope] / [DecryptedMessage] shapes
/// the rest of the messenger already understands.
///
/// Everything here is best-effort *plumbing*; every cryptographic decision
/// lives in `group_sender_keys.dart`.
class GroupSenderKeyCoordinator {
  GroupSenderKeyCoordinator({
    required this.engine,
    required GroupSenderKeySealer sealer,
    required VeilApiClient apiClient,
    required KeyBundleCodec keyBundleCodec,
    required Future<String?> Function() identityPrivateRefLoader,
    required List<int>? Function(String identityPrivateRef) localX25519PrivateParser,
    required List<int>? Function(String identityPrivateRef) localEd25519SeedParser,
    this.onKeysChanged,
    GroupIdentityTrustCheck? trustCheck,
  })  : _sealer = sealer,
        _apiClient = apiClient,
        _keyBundleCodec = keyBundleCodec,
        _identityPrivateRefLoader = identityPrivateRefLoader,
        _localX25519PrivateParser = localX25519PrivateParser,
        _localEd25519SeedParser = localEd25519SeedParser,
        _trustCheck = trustCheck;

  final GroupSenderKeyEngine engine;
  final GroupSenderKeySealer _sealer;
  final VeilApiClient _apiClient;
  final KeyBundleCodec _keyBundleCodec;
  final Future<String?> Function() _identityPrivateRefLoader;
  final List<int>? Function(String) _localX25519PrivateParser;
  final List<int>? Function(String) _localEd25519SeedParser;

  /// Consulted before sealing to a member's device and before accepting a
  /// distribution signer. Null allows every directory identity.
  final GroupIdentityTrustCheck? _trustCheck;

  /// Fired after a peer chain is installed or the group re-keys, so cached
  /// "awaiting sender key" placeholders can be re-decrypted.
  void Function(String conversationId)? onKeysChanged;

  /// Supplied by the controller; resolves the current preview (members,
  /// epoch, flag) for a conversation id.
  ConversationPreview? Function(String conversationId)? conversationLookup;

  // Distributions we have already fetched-and-failed for, keyed by
  // conversation:epoch, so a flood of undecryptable frames doesn't hammer
  // the relay. Cleared on epoch bump / key ingest.
  final Set<String> _pickupAttempted = <String>{};

  // Members our current chain has not reached yet, per conversation: their
  // active device was missing from the directory, the trust check refused
  // it, or the upload failed. Retried on the next prepareSend; an epoch bump
  // replaces the chain and so starts over with every member.
  final Map<String, ({int epoch, Set<String> userIds})> _pending = {};

  // Serializes "do we have a chain / who still needs it / distribute" per
  // conversation so concurrent sends and epoch events cannot interleave.
  final KeyedAsyncLock<String> _distributionLock = KeyedAsyncLock<String>();

  static bool isGroupEnvelope(CryptoEnvelope envelope) =>
      envelope.version == kGroupEnvelopeVersion;

  /// Epoch a group frame was encrypted under, read from the frame header.
  static int? epochOf(CryptoEnvelope envelope) {
    if (!isGroupEnvelope(envelope)) return null;
    return GroupSenderKeyEngine.parseHeader(envelope.ciphertext)?.epoch;
  }

  Future<void> restoreFromSnapshots(Map<String, Map<String, dynamic>> snapshots) =>
      engine.restoreFromSnapshots(snapshots);

  void clearInMemory() {
    engine.clearInMemory();
    _pickupAttempted.clear();
    _pending.clear();
  }

  // ---- send -----------------------------------------------------------------

  /// Makes sure we own a chain for the conversation's current epoch and that
  /// every other member we can reach has been handed it. Returns the epoch to
  /// stamp on the send request.
  Future<int> prepareSend({
    required ConversationPreview conversation,
    required String accessToken,
    required String localUserId,
    required String localDeviceId,
  }) {
    final epoch = conversation.groupEpoch ?? 0;
    return _distributionLock.synchronized(conversation.id, () async {
      final others = _othersIn(conversation, localUserId);
      if (engine.hasOwnSenderKey(
        groupId: conversation.id,
        epoch: epoch,
        localDeviceId: localDeviceId,
      )) {
        final pending = _pending[conversation.id];
        final retry = pending == null || pending.epoch != epoch
            ? const <GroupMember>[]
            : others.where((m) => pending.userIds.contains(m.userId)).toList(growable: false);
        if (retry.isEmpty) {
          _pending.remove(conversation.id);
        } else {
          await _distribute(
            conversationId: conversation.id,
            key: engine.exportOwnSenderKey(conversation.id)!,
            recipients: retry,
            accessToken: accessToken,
          );
        }
        return epoch;
      }
      final key = await engine.ensureOwnSenderKey(
        groupId: conversation.id,
        epoch: epoch,
        localDeviceId: localDeviceId,
      );
      await _distribute(
        conversationId: conversation.id,
        key: key,
        recipients: others,
        accessToken: accessToken,
      );
      onKeysChanged?.call(conversation.id);
      return epoch;
    });
  }

  static List<GroupMember> _othersIn(ConversationPreview conversation, String localUserId) =>
      conversation.members.where((m) => m.userId != localUserId).toList(growable: false);

  /// Seals [key] to every recipient we can and uploads the blobs. Everyone
  /// is marked pending first so a failure part-way leaves them all to retry;
  /// after the upload only the recipients we could not seal to stay pending.
  Future<void> _distribute({
    required String conversationId,
    required GroupSenderKey key,
    required List<GroupMember> recipients,
    required String accessToken,
  }) async {
    final previous = _pending[conversationId];
    _pending[conversationId] = (
      epoch: key.epoch,
      userIds: {
        if (previous != null && previous.epoch == key.epoch) ...previous.userIds,
        ...recipients.map((m) => m.userId),
      },
    );

    final identityRef = await _identityPrivateRefLoader();
    final seed = identityRef == null ? null : _localEd25519SeedParser(identityRef);
    if (seed == null) {
      throw StateError('Local identity key unavailable — cannot sign sender-key distribution.');
    }

    final uploads = <Map<String, dynamic>>[];
    final unreached = <String>{};
    for (final member in recipients) {
      final sealed = await _sealTo(member, key: key, senderIdentityEd25519Seed: seed);
      if (sealed == null) {
        unreached.add(member.userId);
      } else {
        uploads.add(sealed.toUploadJson());
      }
    }
    if (uploads.isNotEmpty) {
      await _apiClient.distributeGroupKeys(
        accessToken,
        conversationId,
        epoch: key.epoch,
        distributions: uploads,
      );
    }
    if (unreached.isEmpty) {
      _pending.remove(conversationId);
    } else {
      _pending[conversationId] = (epoch: key.epoch, userIds: unreached);
    }
  }

  Future<CryptoEnvelope> encryptMessage({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String body,
    required MessageKind messageKind,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) async {
    // Same inner payload as the 1:1 adapter so attachments / expiry ride along.
    final payload = json.encode({
      'body': body,
      'kind': messageKind.name,
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (attachment != null) 'att': _serializeAttachmentRef(attachment),
    });
    final ct = await engine.encrypt(
      groupId: conversation.id,
      localDeviceId: senderDeviceId,
      plaintext: MessagePadding.pad(utf8.encode(payload)),
    );
    return CryptoEnvelope(
      version: kGroupEnvelopeVersion,
      conversationId: conversation.id,
      senderDeviceId: senderDeviceId,
      recipientUserId: '',
      ciphertext: ct.payload,
      nonce: ct.nonce,
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  // ---- receive --------------------------------------------------------------

  Future<DecryptedMessage> decryptMessage(
    CryptoEnvelope envelope, {
    required String accessToken,
    required String localUserId,
  }) async {
    final header = GroupSenderKeyEngine.parseHeader(envelope.ciphertext);
    if (header == null) {
      return _placeholder(envelope, '[Unable to decrypt: invalid envelope]');
    }

    // If we hold no key for this sender (or we never saw the epoch bump),
    // try the relay once before giving up.
    final needPickup = !engine.hasSenderKeyFor(
          groupId: envelope.conversationId,
          senderDeviceId: header.senderDeviceId,
        ) ||
        (engine.currentEpoch(envelope.conversationId) ?? -1) < header.epoch;
    if (needPickup) {
      await _pickupOnce(
        conversationId: envelope.conversationId,
        epoch: header.epoch,
        accessToken: accessToken,
        localUserId: localUserId,
      );
    }

    try {
      final out = await engine.decrypt(
        groupId: envelope.conversationId,
        payload: envelope.ciphertext,
        nonce: envelope.nonce,
      );
      return _decodePayload(out.plaintext);
    } on GroupCryptoException catch (e) {
      switch (e.code) {
        case 'senderKeyMissing':
          return _placeholder(envelope, '[Awaiting sender key — sync required]');
        case 'epochMismatch':
          return _placeholder(envelope, '[Message from a previous group epoch]');
        case 'replayed':
          return _placeholder(envelope, '[Replayed or out-of-window message]');
        default:
          return _placeholder(envelope, '[Decryption failed]');
      }
    } catch (_) {
      return _placeholder(envelope, '[Decryption failed]');
    }
  }

  Future<void> _pickupOnce({
    required String conversationId,
    required int epoch,
    required String accessToken,
    required String localUserId,
  }) async {
    final marker = '$conversationId:$epoch';
    if (!_pickupAttempted.add(marker)) return;
    try {
      await pickupDistributions(
        conversationId: conversationId,
        accessToken: accessToken,
        localUserId: localUserId,
      );
    } catch (_) {
      // Relay unreachable; the frame renders as a placeholder and a later
      // realtime distribution / explicit sync retries.
    }
  }

  /// Offline-pickup path: drains every buffered distribution addressed to us.
  Future<void> pickupDistributions({
    required String conversationId,
    required String accessToken,
    required String localUserId,
  }) async {
    final response = await _apiClient.getGroupKeyDistributions(accessToken, conversationId);
    final epoch = (response['epoch'] as num?)?.toInt();
    final items = (response['distributions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    var ingested = false;
    for (final item in items) {
      final ok = await _ingestSealed(
        conversationId: conversationId,
        epoch: epoch ?? (item['epoch'] as num?)?.toInt() ?? 0,
        fromUserId: item['fromUserId'] as String? ?? '',
        fromDeviceId: item['fromDeviceId'] as String? ?? '',
        encryptedChainKey: item['encryptedChainKey'] as String? ?? '',
        nonce: item['nonce'] as String? ?? '',
        version: item['version'] as String? ?? '',
        localUserId: localUserId,
      );
      ingested = ingested || ok;
    }
    if (ingested) onKeysChanged?.call(conversationId);
  }

  /// `group.key.distribution` realtime event.
  Future<void> handleKeyDistributionEvent(
    Map<String, dynamic> payload, {
    required String localUserId,
  }) async {
    final conversationId = payload['conversationId'] as String? ?? '';
    if (conversationId.isEmpty) return;
    final ok = await _ingestSealed(
      conversationId: conversationId,
      epoch: (payload['epoch'] as num?)?.toInt() ?? 0,
      fromUserId: payload['fromUserId'] as String? ?? '',
      fromDeviceId: payload['fromDeviceId'] as String? ?? '',
      encryptedChainKey: payload['encryptedChainKey'] as String? ?? '',
      nonce: payload['nonce'] as String? ?? '',
      version: payload['version'] as String? ?? '',
      localUserId: localUserId,
    );
    if (ok) onKeysChanged?.call(conversationId);
  }

  /// True when a chain was installed; rejected and no-op distributions
  /// (re-deliveries) both leave the engine untouched.
  Future<bool> _ingestSealed({
    required String conversationId,
    required int epoch,
    required String fromUserId,
    required String fromDeviceId,
    required String encryptedChainKey,
    required String nonce,
    required String version,
    required String localUserId,
  }) async {
    if (fromUserId.isEmpty || fromDeviceId.isEmpty || encryptedChainKey.isEmpty) {
      return false;
    }
    try {
      final distribution = await _openDistribution(
        conversationId: conversationId,
        epoch: epoch,
        fromUserId: fromUserId,
        fromDeviceId: fromDeviceId,
        encryptedChainKey: encryptedChainKey,
        nonce: nonce,
        version: version,
        localUserId: localUserId,
      );
      final installed = await engine.ingestDistribution(distribution);
      if (installed) _pickupAttempted.remove('$conversationId:$epoch');
      return installed;
    } on GroupCryptoException {
      return false;
    } on VeilApiException {
      // The directory could not vouch for the sender right now. Nothing is
      // installed; the relay keeps the blob for the next pickup.
      return false;
    }
  }

  /// Authenticates and unseals one distribution. Throws [GroupCryptoException]
  /// when it must not be ingested, including `untrusted_identity` when the
  /// trust check refuses the signer.
  Future<GroupKeyDistribution> _openDistribution({
    required String conversationId,
    required int epoch,
    required String fromUserId,
    required String fromDeviceId,
    required String encryptedChainKey,
    required String nonce,
    required String version,
    required String localUserId,
  }) async {
    final identityRef = await _identityPrivateRefLoader();
    final xPriv = identityRef == null ? null : _localX25519PrivateParser(identityRef);
    if (xPriv == null) {
      throw const GroupCryptoException('distributionInvalid', 'local identity unavailable');
    }

    // The sender's identity key MUST come from the directory, never from the
    // blob — that is what makes the distribution signature meaningful.
    final member = conversationLookup
        ?.call(conversationId)
        ?.members
        .where((m) => m.userId == fromUserId)
        .firstOrNull;
    if (member == null) {
      throw const GroupCryptoException('distributionInvalid', 'sender is not a member');
    }
    final senderBundle = await _bundleForDevice(member.handle, fromDeviceId);
    if (senderBundle == null || senderBundle.userId != fromUserId) {
      throw const GroupCryptoException('distributionInvalid', 'sender device not in directory');
    }
    if (!await _isTrusted(fromUserId, fromDeviceId, senderBundle.identityPublicKey)) {
      throw const GroupCryptoException('untrusted_identity');
    }

    return _sealer.unseal(
      groupId: conversationId,
      epoch: epoch,
      senderDeviceId: fromDeviceId,
      localUserId: localUserId,
      encryptedChainKey: encryptedChainKey,
      nonce: nonce,
      version: version,
      localIdentityX25519Private: xPriv,
      senderIdentityPublicKey: senderBundle.identityPublicKey,
    );
  }

  /// `group.epoch.bumped` realtime event. The controller has already updated
  /// the preview's epoch (and member list via sync) before calling this.
  Future<void> handleEpochBumped({
    required String conversationId,
    required int epoch,
    required String reason,
    required String userId,
    required String accessToken,
    required String localUserId,
    required String localDeviceId,
  }) =>
      _distributionLock.synchronized(conversationId, () async {
        _pickupAttempted.removeWhere((m) => m.startsWith('$conversationId:'));
        _pending.remove(conversationId);
        if (reason == 'leave' && userId == localUserId) {
          await engine.forget(conversationId);
          onKeysChanged?.call(conversationId);
          return;
        }
        await engine.resetForEpoch(groupId: conversationId, epoch: epoch);
        final conversation = conversationLookup?.call(conversationId);
        if (conversation != null && conversation.useSenderKeys) {
          try {
            final key = await engine.ensureOwnSenderKey(
              groupId: conversationId,
              epoch: epoch,
              localDeviceId: localDeviceId,
            );
            await _distribute(
              conversationId: conversationId,
              key: key,
              recipients: _othersIn(conversation, localUserId),
              accessToken: accessToken,
            );
          } catch (_) {
            // Best effort — whoever was not reached stays pending and the
            // next prepareSend() retries them.
          }
        }
        onKeysChanged?.call(conversationId);
      });

  // ---- directory helpers --------------------------------------------------------

  /// [key] sealed to [member]'s active device, or null when that member
  /// cannot be reached this round: the directory has no active device for
  /// them, the trust check refuses it, or its signed prekey does not verify.
  /// Each of those is about this member alone, so it must not cost the other
  /// members the chain. Failures that are not about the member (offline,
  /// throttled, server error) still abort the round, so the send fails where
  /// the user can see it instead of shipping a frame nobody can read.
  Future<SealedGroupSenderKey?> _sealTo(
    GroupMember member, {
    required GroupSenderKey key,
    required List<int> senderIdentityEd25519Seed,
  }) async {
    final bundle = await _sealableBundleFor(member);
    if (bundle == null) return null;
    try {
      return await _sealer.seal(
        key: key,
        recipientUserId: member.userId,
        recipientIdentityPublicKey: bundle.identityPublicKey,
        recipientSignedPrekeyBundle: bundle.signedPrekeyBundle,
        senderIdentityEd25519Seed: senderIdentityEd25519Seed,
      );
    } on GroupCryptoException {
      return null;
    }
  }

  /// The member's active device bundle, provided the directory lists that
  /// device for that user and the trust check accepts its identity. There is
  /// deliberately no fallback to another listed device: the server must not
  /// get to choose which device receives our chain key.
  Future<KeyBundle?> _sealableBundleFor(GroupMember member) async {
    final Map<String, dynamic> response;
    try {
      response = await _apiClient.getKeyBundle(member.handle);
    } on VeilApiException catch (e) {
      if (_isNoActiveDevice(e)) return null;
      rethrow;
    }
    final activeDeviceId =
        (response['user'] as Map<String, dynamic>?)?['activeDeviceId'] as String?;
    if (activeDeviceId == null) return null;
    final bundle = _findDevice(_decodeBundles(response), activeDeviceId);
    if (bundle == null || bundle.userId != member.userId) return null;
    return await _isTrusted(member.userId, bundle.deviceId, bundle.identityPublicKey)
        ? bundle
        : null;
  }

  /// How the directory reports a user with no trusted active device, e.g.
  /// mid account deletion or after their last device was revoked. Keyed on
  /// the error code, not the bare status: a 404 from an unrouted path is not
  /// about the member and must still fail the round.
  static bool _isNoActiveDevice(VeilApiException error) =>
      error.code == 'active_device_not_found';

  Future<KeyBundle?> _bundleForDevice(String handle, String deviceId) async =>
      _findDevice(_decodeBundles(await _apiClient.getKeyBundle(handle)), deviceId);

  static KeyBundle? _findDevice(List<KeyBundle> bundles, String deviceId) =>
      bundles.where((b) => b.deviceId == deviceId).firstOrNull;

  /// Fails closed: a trust check that throws refuses the identity, exactly as
  /// if it had returned false.
  Future<bool> _isTrusted(String userId, String deviceId, String identityPublicKey) async {
    final check = _trustCheck;
    if (check == null) return true;
    try {
      return await check(userId, deviceId, identityPublicKey);
    } catch (_) {
      return false;
    }
  }

  List<KeyBundle> _decodeBundles(Map<String, dynamic> response) {
    final directory = (response['deviceBundles'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    if (directory.isNotEmpty) {
      return _keyBundleCodec.decodeDirectoryBundles(directory);
    }
    final single = response['bundle'] as Map<String, dynamic>?;
    if (single == null) return const [];
    return [_keyBundleCodec.decodeDirectoryBundle(single)];
  }

  // ---- payload codec ------------------------------------------------------------

  DecryptedMessage _decodePayload(List<int> padded) {
    final map = json.decode(utf8.decode(MessagePadding.unpad(padded))) as Map<String, dynamic>;
    // An unrecognised inner kind renders as text: the outer messageKind is
    // server-controlled and must not decide, say, system chrome.
    final kind = MessageKind.values.firstWhere(
      (k) => k.name == map['kind'],
      orElse: () => MessageKind.text,
    );
    final expiresAtStr = map['expiresAt'] as String?;
    final att = map['att'];
    return DecryptedMessage(
      body: map['body'] as String? ?? '',
      messageKind: kind,
      expiresAt: expiresAtStr == null ? null : DateTime.tryParse(expiresAtStr)?.toLocal(),
      // Only the authenticated inner pointer counts. The outer envelope's
      // attachment is server-controlled and could graft a file onto a
      // genuine message.
      attachment: att is Map<String, dynamic> ? _deserializeAttachmentRef(att) : null,
    );
  }

  DecryptedMessage _placeholder(CryptoEnvelope envelope, String body) =>
      DecryptedMessage(body: body, messageKind: envelope.messageKind);

  static Map<String, dynamic> _serializeAttachmentRef(AttachmentReference a) => {
        'attachmentId': a.attachmentId,
        'storageKey': a.storageKey,
        'contentType': a.contentType,
        'sizeBytes': a.sizeBytes,
        'sha256': a.sha256,
        'encryptedKey': a.encryptedKey,
        'nonce': a.nonce,
        if (a.algorithmHint != null) 'algorithmHint': a.algorithmHint,
      };

  /// Reads both the long-key form written above and the short-key form the
  /// 1:1 adapter writes ('id', 'sk', ...), so a pointer is never dropped just
  /// because the other codec produced it.
  static AttachmentReference _deserializeAttachmentRef(Map<String, dynamic> m) {
    Object? field(String longKey, String shortKey) => m[longKey] ?? m[shortKey];
    return AttachmentReference(
      attachmentId: field('attachmentId', 'id') as String? ?? '',
      storageKey: field('storageKey', 'sk') as String? ?? '',
      contentType: field('contentType', 'ct') as String? ?? 'application/octet-stream',
      sizeBytes: (field('sizeBytes', 'sz') as num?)?.toInt() ?? 0,
      sha256: field('sha256', 'h') as String? ?? '',
      encryptedKey: field('encryptedKey', 'ek') as String? ?? '',
      nonce: field('nonce', 'n') as String? ?? '',
      algorithmHint: field('algorithmHint', 'ah') as String?,
    );
  }
}
