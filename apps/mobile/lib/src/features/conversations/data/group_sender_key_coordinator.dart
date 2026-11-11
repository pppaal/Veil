import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/group_sender_keys.dart';
import '../../../core/crypto/message_padding.dart';
import '../../../core/crypto/payload/inner_payload.dart';
import '../../../core/network/keys_api.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/util/keyed_async_lock.dart';
import 'conversation_models.dart';

/// Decides whether a directory identity may take part in a group's Sender
/// Keys: whether we seal our chain key to that device, and whether we accept
/// a chain it signed.
typedef GroupIdentityTrustCheck = Future<bool> Function(
  String conversationId,
  String userId,
  String deviceId,
  String identityPublicKey,
);

/// Glue between the pure [GroupSenderKeyEngine] and the app: decides when we
/// need a fresh chain, fans our chain key out to every trusted device of the
/// other members through the server relay, picks up members' chain keys
/// addressed to us, and turns group frames into the same [CryptoEnvelope] /
/// [DecryptedMessage] shapes the rest of the messenger already understands.
///
/// Delivery is tracked per device, never per member: a member's device that
/// is approved, added or transferred to after the member got our chain
/// still needs a copy of its own.
///
/// Everything here is best-effort *plumbing*; every cryptographic decision
/// lives in `group_sender_keys.dart`.
class GroupSenderKeyCoordinator {
  GroupSenderKeyCoordinator({
    required this.engine,
    required GroupSenderKeySealer sealer,
    required VeilApiClient apiClient,
    required KeysApi keys,
    required Future<String?> Function() identityPrivateRefLoader,
    required List<int>? Function(String identityPrivateRef) localX25519PrivateParser,
    required List<int>? Function(String identityPrivateRef) localEd25519SeedParser,
    required ConversationPreview? Function(String conversationId) conversationLookup,
    void Function(String conversationId)? onKeysChanged,
    GroupIdentityTrustCheck? trustCheck,
    DateTime Function()? clock,
  })  : _sealer = sealer,
        _apiClient = apiClient,
        _keys = keys,
        _identityPrivateRefLoader = identityPrivateRefLoader,
        _localX25519PrivateParser = localX25519PrivateParser,
        _localEd25519SeedParser = localEd25519SeedParser,
        _conversationLookup = conversationLookup,
        _onKeysChanged = onKeysChanged,
        _trustCheck = trustCheck,
        _clock = clock ?? DateTime.now;

  /// How long a member's directory entry is reused for sending. It bounds
  /// how late a device the member adds is handed our chain, without asking
  /// the directory about every member on every send.
  static const Duration memberDevicesTtl = Duration(minutes: 10);

  final GroupSenderKeyEngine engine;
  final GroupSenderKeySealer _sealer;
  final VeilApiClient _apiClient;
  final KeysApi _keys;
  final Future<String?> Function() _identityPrivateRefLoader;
  final List<int>? Function(String) _localX25519PrivateParser;
  final List<int>? Function(String) _localEd25519SeedParser;

  /// Resolves the current preview (members, epoch, flag) for a conversation.
  final ConversationPreview? Function(String conversationId) _conversationLookup;

  /// Fired after a peer chain is installed or the group re-keys, so content
  /// still awaiting a sender key can be decrypted again.
  final void Function(String conversationId)? _onKeysChanged;

  /// Consulted before sealing to a member's device and before accepting a
  /// distribution signer. Null allows every directory identity.
  final GroupIdentityTrustCheck? _trustCheck;
  final DateTime Function() _clock;

  // Members' directory entries by user id, with when they were fetched.
  final Map<String, (KeyDirectoryEntry, DateTime)> _memberDevices = {};

  // Distributions we have already fetched-and-failed for, keyed by
  // conversation:epoch, so a flood of undecryptable frames doesn't hammer
  // the relay. Cleared on epoch bump / key ingest.
  final Set<String> _pickupAttempted = <String>{};

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
    _memberDevices.clear();
  }

  // ---- send -----------------------------------------------------------------

  /// Makes sure we own a chain for the conversation's current epoch and that
  /// every trusted device of the other members we can reach has been handed
  /// it. Returns the epoch to stamp on the send request.
  ///
  /// The engine persists which devices hold the chain together with the
  /// chain. So, restarts included, a device it has not reached (its member
  /// has no trusted device in the directory, the trust check refused it until
  /// the user approves it, its upload failed, its member added it since) is
  /// handed it on a later send, and a device it has reached is not sent it
  /// again: the relay would replace its still-buffered copy with one that
  /// starts at a later counter, losing it the frames in between.
  Future<int> prepareSend({
    required ConversationPreview conversation,
    required String accessToken,
    required String localUserId,
    required String localDeviceId,
  }) {
    final epoch = conversation.groupEpoch ?? 0;
    return _distributionLock.synchronized(conversation.id, () async {
      final isNewChain = !engine.hasOwnSenderKey(
        groupId: conversation.id,
        epoch: epoch,
        localDeviceId: localDeviceId,
      );
      final key = await engine.ensureOwnSenderKey(
        groupId: conversation.id,
        epoch: epoch,
        localDeviceId: localDeviceId,
      );
      final reachedBefore = engine.deliveredTo(key);
      try {
        await _distribute(
          conversationId: conversation.id,
          key: key,
          recipients: _othersIn(conversation, localUserId),
          accessToken: accessToken,
        );
      } catch (_) {
        // While no device is known to hold this chain, a frame sent under it
        // could be unreadable to everyone, so the send fails. Once one does,
        // failing to reach the rest must not cost it the message; the rest
        // stay unrecorded and the next send tries again.
        if (reachedBefore.isEmpty) rethrow;
      }
      if (isNewChain) _onKeysChanged?.call(conversation.id);
      return epoch;
    });
  }

  static List<GroupMember> _othersIn(ConversationPreview conversation, String localUserId) =>
      conversation.members.where((m) => m.userId != localUserId).toList(growable: false);

  /// Seals [key] to every trusted device of the recipients that does not
  /// hold it yet, each blob addressed to its device, uploads the blobs, and
  /// only then records those devices as holding the chain. A device that
  /// could not be sealed to, or a failed upload, stays unrecorded for the
  /// next prepareSend.
  Future<void> _distribute({
    required String conversationId,
    required GroupSenderKey key,
    required List<GroupMember> recipients,
    required String accessToken,
  }) async {
    final reached = engine.deliveredTo(key);
    final targets = <(GroupMember, KeyBundle)>[];
    for (final member in recipients) {
      targets.addAll(await _devicesToReach(conversationId, member, reached: reached, accessToken: accessToken));
    }
    if (targets.isEmpty) return;

    final identityRef = await _identityPrivateRefLoader();
    final seed = identityRef == null ? null : _localEd25519SeedParser(identityRef);
    if (seed == null) {
      throw StateError('Local identity key unavailable — cannot sign sender-key distribution.');
    }
    final sealed = <SealedGroupSenderKey>[];
    final sealedTo = <String>[];
    for (final (member, bundle) in targets) {
      try {
        sealed.add(await _sealer.seal(
          key: key,
          recipientUserId: member.userId,
          recipientDeviceId: bundle.deviceId,
          recipientIdentityPublicKey: bundle.identityPublicKey,
          recipientSignedPrekeyBundle: bundle.signedPrekeyBundle,
          senderIdentityEd25519Seed: seed,
        ));
        sealedTo.add(_deviceAddress(member.userId, bundle.deviceId));
      } on GroupCryptoException {
        // A signed prekey that does not verify is about that device alone.
        continue;
      }
    }
    if (sealed.isEmpty) return;
    await _apiClient.distributeGroupKeys(
      accessToken,
      conversationId,
      epoch: key.epoch,
      distributions: [for (final blob in sealed) blob.toUploadJson()],
    );
    await engine.recordDelivered(key, sealedTo);
  }

  /// How the delivery ledger names one device of one member.
  static String _deviceAddress(String userId, String deviceId) =>
      '${Uri.encodeComponent(userId)}/${Uri.encodeComponent(deviceId)}';

  Future<CryptoEnvelope> encryptMessage({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String body,
    required MessageKind messageKind,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) async {
    // The 1:1 inner payload, so kind, expiry and attachments read the same
    // way on both paths.
    final payload = InnerPayload(body: body, kind: messageKind, expiresAt: expiresAt, attachment: attachment);
    final ct = await engine.encrypt(
      groupId: conversation.id,
      localDeviceId: senderDeviceId,
      plaintext: MessagePadding.pad(payload.encode()),
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
      return _failure(DecryptStatus.failed, 'invalid_envelope');
    }
    // The messenger attributes a message (and a reaction) to the relay's
    // outer sender, but only the header's device is authenticated: its
    // chain is what the frame must verify against.
    if (header.senderDeviceId != envelope.senderDeviceId) {
      return _failure(DecryptStatus.failed, 'sender_mismatch');
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

    final GroupPlaintext out;
    try {
      out = await engine.decrypt(
        groupId: envelope.conversationId,
        payload: envelope.ciphertext,
        nonce: envelope.nonce,
      );
    } on GroupCryptoException catch (e) {
      return switch (e.code) {
        'senderKeyMissing' => _failure(DecryptStatus.awaitingKey, e.code),
        'replayed' => _failure(DecryptStatus.replayed, e.code),
        _ => _failure(DecryptStatus.failed, e.code),
      };
    }
    try {
      // An unrecognised inner kind reads as text: the outer messageKind is
      // server-controlled and must not decide, say, system chrome.
      final payload = InnerPayload.decode(MessagePadding.unpad(out.plaintext), fallbackKind: MessageKind.text);
      return DecryptedMessage(
        body: payload.body,
        messageKind: payload.kind,
        expiresAt: payload.expiresAt,
        // Only the authenticated inner pointer counts. The outer envelope's
        // attachment is server-controlled and could graft a file onto a
        // genuine message.
        attachment: payload.attachment,
      );
    } on Object {
      // Authenticated by a member, yet not a payload: still never a crash.
      return _failure(DecryptStatus.failed, 'malformed_payload');
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
      // Relay unreachable; the frame stays awaiting its key and a later
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
        accessToken: accessToken,
      );
      ingested = ingested || ok;
    }
    if (ingested) _onKeysChanged?.call(conversationId);
  }

  /// `group.key.distribution` realtime event.
  Future<void> handleKeyDistributionEvent(
    Map<String, dynamic> payload, {
    required String localUserId,
    required String accessToken,
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
      accessToken: accessToken,
    );
    if (ok) _onKeysChanged?.call(conversationId);
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
    required String accessToken,
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
        accessToken: accessToken,
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
    } on FormatException {
      // Nor could it when its answer was malformed.
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
    required String accessToken,
  }) async {
    final identityRef = await _identityPrivateRefLoader();
    final xPriv = identityRef == null ? null : _localX25519PrivateParser(identityRef);
    if (xPriv == null) {
      throw const GroupCryptoException('distributionInvalid', 'local identity unavailable');
    }

    // The sender's identity key MUST come from the directory, never from the
    // blob — that is what makes the distribution signature meaningful — and
    // the pins decide whether that key is the member's at all.
    final member = _conversationLookup(conversationId)
        ?.members
        .where((m) => m.userId == fromUserId)
        .firstOrNull;
    if (member == null) {
      throw const GroupCryptoException('distributionInvalid', 'sender is not a member');
    }
    final entry = await _keys.lookup(member.handle, accessToken: accessToken, claim: KeyClaim.none);
    final sender = entry.userId == fromUserId ? entry.device(fromDeviceId) : null;
    if (sender == null) {
      throw const GroupCryptoException('distributionInvalid', 'sender device not in directory');
    }
    final senderKey = sender.bundle.identityPublicKey;
    if (!await _isTrusted(conversationId, fromUserId, fromDeviceId, senderKey)) {
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
      senderIdentityPublicKey: senderKey,
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
        if (reason == 'leave' && userId == localUserId) {
          await engine.forget(conversationId);
          _onKeysChanged?.call(conversationId);
          return;
        }
        await engine.resetForEpoch(groupId: conversationId, epoch: epoch);
        final conversation = _conversationLookup(conversationId);
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
            // Best effort: whoever was not reached stays unrecorded and the
            // next prepareSend() hands them the chain.
          }
        }
        _onKeysChanged?.call(conversationId);
      });

  // ---- directory helpers --------------------------------------------------------

  /// [member]'s devices in the directory that [reached] does not list and
  /// the trust check accepts. Empty when the member has no trusted device in
  /// the directory, or every device is refused or already reached: each is
  /// about this member alone and must not cost the others the chain.
  /// Failures that are not about the member (offline, throttled, server
  /// error) abort the round; prepareSend decides whether that fails the send.
  Future<List<(GroupMember, KeyBundle)>> _devicesToReach(
    String conversationId,
    GroupMember member, {
    required Set<String> reached,
    required String accessToken,
  }) async {
    final entry = await _sendingEntryOf(member, accessToken);
    if (entry == null) return const [];
    final devices = <(GroupMember, KeyBundle)>[];
    for (final device in entry.devices) {
      final bundle = device.bundle;
      if (reached.contains(_deviceAddress(member.userId, bundle.deviceId))) continue;
      if (await _isTrusted(conversationId, member.userId, bundle.deviceId, bundle.identityPublicKey)) {
        devices.add((member, bundle));
      }
    }
    return devices;
  }

  /// The member's directory entry for sealing, reused for
  /// [memberDevicesTtl]. A member the directory has no trusted device for is
  /// not remembered, so the next send asks again.
  Future<KeyDirectoryEntry?> _sendingEntryOf(GroupMember member, String accessToken) async {
    final now = _clock();
    final cached = _memberDevices[member.userId];
    if (cached != null && now.difference(cached.$2) < memberDevicesTtl) return cached.$1;
    final entry = await _directoryEntryOf(member, accessToken);
    if (entry == null) {
      _memberDevices.remove(member.userId);
    } else {
      _memberDevices[member.userId] = (entry, now);
    }
    return entry;
  }

  /// The member's directory entry, provided the directory answers for that
  /// very user; null when it has no trusted device for them. A malformed
  /// answer vouches for none of the member's devices either, and must not
  /// keep the chain from the other members.
  Future<KeyDirectoryEntry?> _directoryEntryOf(GroupMember member, String accessToken) async {
    final KeyDirectoryEntry entry;
    try {
      entry = await _keys.lookup(member.handle, accessToken: accessToken, claim: KeyClaim.none);
    } on VeilApiException catch (e) {
      if (_isNoActiveDevice(e)) return null;
      rethrow;
    } on FormatException {
      return null;
    }
    return entry.userId == member.userId ? entry : null;
  }

  /// How the directory reports a user with no trusted active device, e.g.
  /// mid account deletion or after their last device was revoked. Keyed on
  /// the error code, not the bare status: a 404 from an unrouted path is not
  /// about the member and must still fail the round.
  static bool _isNoActiveDevice(VeilApiException error) =>
      error.code == 'active_device_not_found';

  /// Fails closed: a trust check that throws refuses the identity, exactly as
  /// if it had returned false.
  Future<bool> _isTrusted(String conversationId, String userId, String deviceId, String identityPublicKey) async {
    final check = _trustCheck;
    if (check == null) return true;
    try {
      return await check(conversationId, userId, deviceId, identityPublicKey);
    } catch (_) {
      return false;
    }
  }

  static DecryptedMessage _failure(DecryptStatus status, String reason) =>
      // Nothing was authenticated, so the server-controlled outer kind must
      // not decide how the failure renders (e.g. as system chrome).
      DecryptedMessage(body: '', messageKind: MessageKind.text, status: status, failureReason: reason);
}
