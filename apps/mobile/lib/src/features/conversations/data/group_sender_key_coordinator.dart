import 'dart:convert';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/group_sender_keys.dart';
import '../../../core/crypto/message_padding.dart';
import '../../../core/network/veil_api_client.dart';
import 'conversation_models.dart';

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
  })  : _sealer = sealer,
        _apiClient = apiClient,
        _keyBundleCodec = keyBundleCodec,
        _identityPrivateRefLoader = identityPrivateRefLoader,
        _localX25519PrivateParser = localX25519PrivateParser,
        _localEd25519SeedParser = localEd25519SeedParser;

  final GroupSenderKeyEngine engine;
  final GroupSenderKeySealer _sealer;
  final VeilApiClient _apiClient;
  final KeyBundleCodec _keyBundleCodec;
  final Future<String?> Function() _identityPrivateRefLoader;
  final List<int>? Function(String) _localX25519PrivateParser;
  final List<int>? Function(String) _localEd25519SeedParser;

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
  }

  // ---- send -----------------------------------------------------------------

  /// Makes sure we own a chain for the conversation's current epoch and that
  /// every other member has been handed it. Returns the epoch to stamp on
  /// the send request.
  Future<int> prepareSend({
    required ConversationPreview conversation,
    required String accessToken,
    required String localUserId,
    required String localDeviceId,
  }) async {
    final epoch = conversation.groupEpoch ?? 0;
    if (engine.hasOwnSenderKey(
      groupId: conversation.id,
      epoch: epoch,
      localDeviceId: localDeviceId,
    )) {
      return epoch;
    }
    final key = await engine.ensureOwnSenderKey(
      groupId: conversation.id,
      epoch: epoch,
      localDeviceId: localDeviceId,
    );
    await _distribute(
      conversation: conversation,
      key: key,
      accessToken: accessToken,
      localUserId: localUserId,
    );
    onKeysChanged?.call(conversation.id);
    return epoch;
  }

  Future<void> _distribute({
    required ConversationPreview conversation,
    required GroupSenderKey key,
    required String accessToken,
    required String localUserId,
  }) async {
    final identityRef = await _identityPrivateRefLoader();
    final seed = identityRef == null ? null : _localEd25519SeedParser(identityRef);
    if (seed == null) {
      throw StateError('Local identity key unavailable — cannot sign sender-key distribution.');
    }

    final uploads = <Map<String, dynamic>>[];
    for (final member in conversation.members) {
      if (member.userId == localUserId) continue;
      final bundle = await _activeBundleFor(member.handle);
      if (bundle == null) continue;
      final sealed = await _sealer.seal(
        key: key,
        recipientUserId: member.userId,
        recipientIdentityPublicKey: bundle.identityPublicKey,
        recipientSignedPrekeyBundle: bundle.signedPrekeyBundle,
        senderIdentityEd25519Seed: seed,
      );
      uploads.add(sealed.toUploadJson());
    }
    if (uploads.isEmpty) return; // solo group — nothing to hand out yet
    await _apiClient.distributeGroupKeys(
      accessToken,
      conversation.id,
      epoch: key.epoch,
      distributions: uploads,
    );
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
      return _decodePayload(envelope, out.plaintext);
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
    final identityRef = await _identityPrivateRefLoader();
    final xPriv = identityRef == null ? null : _localX25519PrivateParser(identityRef);
    if (xPriv == null) return false;

    // The sender's identity key MUST come from the directory, never from the
    // blob — that is what makes the distribution signature meaningful.
    final conversation = conversationLookup?.call(conversationId);
    final member = conversation?.members.cast<GroupMember?>().firstWhere(
          (m) => m?.userId == fromUserId,
          orElse: () => null,
        );
    if (member == null) return false;
    final senderBundle = await _bundleForDevice(member.handle, fromDeviceId);
    if (senderBundle == null) return false;

    try {
      final key = await _sealer.unseal(
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
      await engine.ingestSenderKey(key);
      _pickupAttempted.remove('$conversationId:$epoch');
      return true;
    } on GroupCryptoException {
      return false;
    }
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
  }) async {
    _pickupAttempted.removeWhere((m) => m.startsWith('$conversationId:'));
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
          conversation: conversation.copyWith(groupEpoch: epoch),
          key: key,
          accessToken: accessToken,
          localUserId: localUserId,
        );
      } catch (_) {
        // Best effort — prepareSend() re-keys and redistributes on next send.
      }
    }
    onKeysChanged?.call(conversationId);
  }

  // ---- directory helpers --------------------------------------------------------

  Future<List<KeyBundle>> _fetchBundles(String handle) async =>
      _decodeBundles(await _apiClient.getKeyBundle(handle));

  Future<KeyBundle?> _activeBundleFor(String handle) async {
    final response = await _apiClient.getKeyBundle(handle);
    final activeDeviceId =
        (response['user'] as Map<String, dynamic>?)?['activeDeviceId'] as String?;
    final bundles = await _decodeBundles(response);
    if (bundles.isEmpty) return null;
    return bundles.cast<KeyBundle?>().firstWhere(
          (b) => b?.deviceId == activeDeviceId,
          orElse: () => bundles.first,
        );
  }

  Future<KeyBundle?> _bundleForDevice(String handle, String deviceId) async {
    final bundles = await _fetchBundles(handle);
    if (bundles.isEmpty) return null;
    return bundles.cast<KeyBundle?>().firstWhere(
          (b) => b?.deviceId == deviceId,
          orElse: () => null,
        );
  }

  Future<List<KeyBundle>> _decodeBundles(Map<String, dynamic> response) async {
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

  DecryptedMessage _decodePayload(CryptoEnvelope envelope, List<int> padded) {
    final map = json.decode(utf8.decode(MessagePadding.unpad(padded))) as Map<String, dynamic>;
    final kind = MessageKind.values.firstWhere(
      (k) => k.name == map['kind'],
      orElse: () => envelope.messageKind,
    );
    final expiresAtStr = map['expiresAt'] as String?;
    final att = map['att'];
    return DecryptedMessage(
      body: map['body'] as String? ?? '',
      messageKind: kind,
      expiresAt: expiresAtStr == null ? null : DateTime.tryParse(expiresAtStr)?.toLocal(),
      attachment: att is Map<String, dynamic> ? _deserializeAttachmentRef(att) : envelope.attachment,
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

  static AttachmentReference _deserializeAttachmentRef(Map<String, dynamic> m) =>
      AttachmentReference(
        attachmentId: m['attachmentId'] as String? ?? '',
        storageKey: m['storageKey'] as String? ?? '',
        contentType: m['contentType'] as String? ?? 'application/octet-stream',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: m['sha256'] as String? ?? '',
        encryptedKey: m['encryptedKey'] as String? ?? '',
        nonce: m['nonce'] as String? ?? '',
        algorithmHint: m['algorithmHint'] as String?,
      );
}
