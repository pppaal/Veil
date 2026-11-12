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

  /// How long the members' directory entries are reused. It bounds how late
  /// a device a member adds is handed our chain, without asking the
  /// directory on every send.
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

  // The other members' directory entries, by conversation.
  final Map<String, _MemberDirectory> _memberDirectories = {};
  final Map<String, Future<_MemberDirectory>> _memberDirectoryFetches = {};

  // Pickups that settled every distribution buffered for us, keyed by
  // conversation:epoch, so a flood of undecryptable frames doesn't hammer
  // the relay. Cleared on epoch bump / key ingest. A pickup that met a
  // transient failure is not recorded, so the next frame tries again.
  final Set<String> _pickupAttempted = <String>{};
  final Map<String, Future<void>> _pickups = {};

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
    _memberDirectories.clear();
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
          epoch: epoch,
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
    required int epoch,
    required GroupSenderKey key,
    required List<GroupMember> recipients,
    required String accessToken,
  }) async {
    final reached = engine.deliveredTo(key);
    final entryOf = _directoryRound(conversationId, epoch: epoch, accessToken: accessToken);
    final targets = <(GroupMember, KeyBundle)>[];
    for (final member in recipients) {
      final entry = await entryOf(member.userId);
      if (entry == null) continue;
      targets.addAll(await _devicesToReach(conversationId, member, entry, reached: reached));
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

  // Concurrent frames share one pickup, and a pickup counts as done for the
  // epoch only once every distribution it found was installed or refused
  // for good: one that met a throttled or unreachable directory would
  // otherwise strand that member's chain key for the rest of the epoch.
  Future<void> _pickupOnce({
    required String conversationId,
    required int epoch,
    required String accessToken,
    required String localUserId,
  }) {
    final marker = '$conversationId:$epoch';
    if (_pickupAttempted.contains(marker)) return Future<void>.value();
    return _pickups[marker] ??= () async {
      try {
        final settled = await pickupDistributions(
          conversationId: conversationId,
          accessToken: accessToken,
          localUserId: localUserId,
        );
        if (settled) _pickupAttempted.add(marker);
      } catch (_) {
        // Relay unreachable; the frame stays awaiting its key and the next
        // one tries again.
      } finally {
        _pickups.remove(marker);
      }
    }();
  }

  /// Offline-pickup path: drains every buffered distribution addressed to
  /// us. Returns false when one of them met a transient failure and stays
  /// for a later pickup.
  Future<bool> pickupDistributions({
    required String conversationId,
    required String accessToken,
    required String localUserId,
  }) async {
    final response = await _apiClient.getGroupKeyDistributions(accessToken, conversationId);
    final epoch = (response['epoch'] as num?)?.toInt();
    final items = (response['distributions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    var ingested = false;
    var settled = true;
    final entryOf = _directoryRound(conversationId, epoch: epoch ?? 0, accessToken: accessToken);
    for (final item in items) {
      final outcome = await _ingestSealed(
        conversationId: conversationId,
        epoch: epoch ?? (item['epoch'] as num?)?.toInt() ?? 0,
        fromUserId: item['fromUserId'] as String? ?? '',
        fromDeviceId: item['fromDeviceId'] as String? ?? '',
        encryptedChainKey: item['encryptedChainKey'] as String? ?? '',
        nonce: item['nonce'] as String? ?? '',
        version: item['version'] as String? ?? '',
        localUserId: localUserId,
        entryOf: entryOf,
      );
      ingested = ingested || outcome == _Ingest.installed;
      settled = settled && outcome != _Ingest.retry;
    }
    if (ingested) _onKeysChanged?.call(conversationId);
    return settled;
  }

  /// `group.key.distribution` realtime event.
  Future<void> handleKeyDistributionEvent(
    Map<String, dynamic> payload, {
    required String localUserId,
    required String accessToken,
  }) async {
    final conversationId = payload['conversationId'] as String? ?? '';
    if (conversationId.isEmpty) return;
    final epoch = (payload['epoch'] as num?)?.toInt() ?? 0;
    final outcome = await _ingestSealed(
      conversationId: conversationId,
      epoch: epoch,
      fromUserId: payload['fromUserId'] as String? ?? '',
      fromDeviceId: payload['fromDeviceId'] as String? ?? '',
      encryptedChainKey: payload['encryptedChainKey'] as String? ?? '',
      nonce: payload['nonce'] as String? ?? '',
      version: payload['version'] as String? ?? '',
      localUserId: localUserId,
      entryOf: _directoryRound(conversationId, epoch: epoch, accessToken: accessToken),
    );
    if (outcome == _Ingest.installed) _onKeysChanged?.call(conversationId);
  }

  /// Whether a chain was installed. Refused and no-op distributions
  /// (re-deliveries) both leave the engine untouched; so does one the
  /// directory could not vouch for right now, which the relay keeps for the
  /// next pickup.
  Future<_Ingest> _ingestSealed({
    required String conversationId,
    required int epoch,
    required String fromUserId,
    required String fromDeviceId,
    required String encryptedChainKey,
    required String nonce,
    required String version,
    required String localUserId,
    required _MemberEntryLookup entryOf,
  }) async {
    if (fromUserId.isEmpty || fromDeviceId.isEmpty || encryptedChainKey.isEmpty) {
      return _Ingest.refused;
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
        entryOf: entryOf,
      );
      if (!await engine.ingestDistribution(distribution)) return _Ingest.refused;
      _pickupAttempted.remove('$conversationId:$epoch');
      return _Ingest.installed;
    } on GroupCryptoException {
      return _Ingest.refused;
    } on VeilApiException {
      // The directory could not vouch for the sender right now (throttled,
      // offline, a server error).
      return _Ingest.retry;
    } on FormatException {
      // Nor could it when its answer was malformed.
      return _Ingest.retry;
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
    required _MemberEntryLookup entryOf,
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
    final sender = (await entryOf(fromUserId, deviceId: fromDeviceId))?.device(fromDeviceId);
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
              epoch: epoch,
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

  /// The devices of [member]'s [entry] that [reached] does not list and the
  /// trust check accepts. Empty when every device is refused or already
  /// reached: each is about this member alone and must not cost the others
  /// the chain.
  Future<List<(GroupMember, KeyBundle)>> _devicesToReach(
    String conversationId,
    GroupMember member,
    KeyDirectoryEntry entry, {
    required Set<String> reached,
  }) async {
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

  /// Resolves members' directory entries for one sending round or one batch
  /// of received distributions. The entry of a member is for sealing to
  /// their devices or for checking a distribution [deviceId] signed; null
  /// when the directory lists no trusted device for them (mid account
  /// deletion, or after their last device was revoked), or not [deviceId]:
  /// that is about this member alone.
  ///
  /// Every member comes from one GET /keys/group/:conversationId, reused for
  /// sending and receiving while it is about [epoch] or a later one and
  /// younger than [memberDevicesTtl], never from one lookup per member: the
  /// directory allows a device ten handle lookups a minute and a group has
  /// up to 25 members. When a reused answer lacks a member or device, the
  /// round asks once more; what the newer answer lacks too is taken as
  /// absent until it is replaced. Failures that are not about a member
  /// (offline, throttled, server error) are thrown: a sending round then
  /// aborts, and a distribution stays for a later pickup.
  _MemberEntryLookup _directoryRound(String conversationId, {required int epoch, required String accessToken}) {
    _MemberDirectory? directory;
    var askedThisRound = false;
    Future<_MemberDirectory> fetch() async {
      askedThisRound = true;
      return directory = await _fetchMemberDirectory(conversationId, accessToken);
    }

    return (userId, {deviceId}) async {
      bool lists(_MemberDirectory directory) {
        final entry = directory.keys.members[userId];
        return entry != null && (deviceId == null || entry.device(deviceId) != null);
      }

      final cached = _memberDirectories[conversationId];
      var current = directory ??
          (cached != null && cached.keys.epoch >= epoch && _clock().difference(cached.fetchedAt) < memberDevicesTtl
              ? directory = cached
              : await fetch());
      final missing = deviceId == null ? Uri.encodeComponent(userId) : _deviceAddress(userId, deviceId);
      if (!lists(current) && !askedThisRound && !current.confirmedMissing.contains(missing)) {
        current = await fetch();
      }
      if (lists(current)) return current.keys.members[userId];
      current.confirmedMissing.add(missing);
      return null;
    };
  }

  // Concurrent rounds and distributions share one request.
  Future<_MemberDirectory> _fetchMemberDirectory(String conversationId, String accessToken) =>
      _memberDirectoryFetches[conversationId] ??= () async {
        try {
          final keys = await _keys.groupMemberKeys(conversationId, accessToken: accessToken);
          return _memberDirectories[conversationId] = _MemberDirectory(keys, _clock());
        } finally {
          _memberDirectoryFetches.remove(conversationId);
        }
      }();

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

/// A member's directory entry within one round; see
/// GroupSenderKeyCoordinator._directoryRound.
typedef _MemberEntryLookup = Future<KeyDirectoryEntry?> Function(String userId, {String? deviceId});

/// What became of one distribution.
enum _Ingest {
  installed,

  /// Refused for good, or a re-delivery of a chain already held.
  refused,

  /// The directory could not vouch for the signer right now.
  retry,
}

/// One answer of GET /keys/group/:conversationId and when it came.
class _MemberDirectory {
  _MemberDirectory(this.keys, this.fetchedAt);

  final GroupMemberKeys keys;
  final DateTime fetchedAt;

  /// Members and devices this answer was asked again for and still lacked:
  /// not asked for again until the answer is replaced.
  final Set<String> confirmedMissing = {};
}
