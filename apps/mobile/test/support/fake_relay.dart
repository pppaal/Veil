import 'dart:async';
import 'dart:io';

import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';

// In-process stand-in for the VEIL relay, generalised from the `_Relay` in
// group_sender_keys_controller_test.dart: several parties, direct and group
// conversations, a key directory serving whatever each party's own adapter
// generated, and server-side fan-out of message.new / read / delivered. It
// only ever sees opaque envelopes, like the real server.

class RelayParty {
  RelayParty({
    required this.handle,
    required this.userId,
    required this.deviceId,
    required this.identity,
  });

  final String handle;
  final String userId;
  final String deviceId;
  final DeviceIdentityMaterial identity;

  Map<String, dynamic> get bundleJson => {
        'userId': userId,
        'deviceId': deviceId,
        'handle': handle,
        'identityPublicKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
      };
}

class RelayConversation {
  RelayConversation({
    required this.id,
    required this.type,
    required this.memberHandles,
    required this.createdAt,
    this.useSenderKeys = false,
    this.name,
  });

  final String id;
  final String type;
  final List<String> memberHandles;
  final DateTime createdAt;
  // A group's name, which only GET /conversations/group/:id answers with.
  final String? name;
  // Settable so a test can play a relay that lies about it.
  bool useSenderKeys;
  int epoch = 0;
  final List<Map<String, dynamic>> messages = [];
}

/// An attachment row, with the fields the API's ticket rules look at.
class RelayAttachment {
  RelayAttachment({
    required this.uploaderDeviceId,
    required this.sha256,
    required this.sizeBytes,
  });

  final String uploaderDeviceId;
  final String sha256;
  final int sizeBytes;
  String uploadStatus = 'pending';
}

final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

class FakeRelay {
  final Map<String, RelayParty> partiesByHandle = {};
  final Map<String, RelayConversation> conversations = {};
  final Map<String, FakeRelayRealtime> _realtimeByHandle = {};
  final Map<String, FakeRelayClient> _clientsByHandle = {};

  /// Directory answers that replace a party's real bundle (identity swaps).
  final Map<String, Map<String, dynamic>> bundleOverrides = {};

  /// Extra trusted devices the directory lists for a handle, beside its
  /// active one (a ghost device a hostile server injects, for instance).
  final Map<String, List<Map<String, dynamic>>> extraDevices = {};

  /// Handles the relay lists some accounts under, by the handle of the
  /// party it lies to: {viewer: {real handle: listed handle}}. The listing
  /// keeps each member's real user id, as a relay that relabels does. It
  /// covers conversation members and the viewer's blocked accounts.
  final Map<String, Map<String, String>> listedHandles = {};

  /// Signed-prekey bundles devices published with PUT /keys/signed-prekey.
  final Map<String, String> publishedSignedPrekeys = {};

  /// Unclaimed one-time prekeys each device published, in key id order.
  final Map<String, List<OneTimePrekey>> oneTimePrekeys = {};

  /// Every one-time prekey the directory handed out, by device.
  final Map<String, List<int>> claimedOneTimePrekeys = {};

  /// Sealed sender-key distributions waiting for pickup, by recipient user.
  final Map<String, List<Map<String, dynamic>>> groupDistributions = {};

  /// Uploaded attachment blobs, by attachment id.
  final Map<String, List<int>> uploadedBlobs = {};

  /// Attachment rows by id, and the id of every upload ticket issued.
  final Map<String, RelayAttachment> attachments = {};
  final List<String> uploadTickets = [];

  /// The content type each upload-ticket request declared.
  final List<Object?> uploadTicketContentTypes = [];

  Duration uploadTicketLifetime = const Duration(minutes: 10);

  /// Upload completions to answer with a transient failure, which leaves the
  /// sender's draft holding its ticket.
  int failUploadCompletions = 0;

  /// Simulates a server that drops the outer expiresAt on relay.
  bool stripOuterExpiresAt = false;

  /// Rewrites the message a send is acknowledged with, as a lying relay
  /// would; the stored row is unchanged.
  Map<String, dynamic> Function(Map<String, dynamic> stored)? rewriteAck;

  /// Messages per history page; null serves the whole history at once.
  int? messagePageSize;

  /// Blocks as SafetyService keeps them: each blocker's user id, then the
  /// user ids they blocked with when, newest last.
  final Map<String, Map<String, DateTime>> blocks = {};

  /// The mutes each user sent (POST /safety/mutes/:conversationId): user
  /// id, then conversation id and how many seconds, null for no end.
  final Map<String, Map<String, int?>> mutes = {};

  /// The abuse reports filed, each with the fields the client passed and
  /// who filed it.
  final List<({String reporterUserId, Map<String, String> fields})> reports = [];

  /// Reports to refuse as the throttle does (six a minute) before any is
  /// taken again.
  int refuseReports = 0;

  /// While set, a report waits for it before the relay answers, as a slow
  /// network would.
  Completer<void>? reportGate;

  /// Whether either of two users blocked the other, as
  /// SafetyService.isBlockedEitherWay answers it.
  bool blockedEitherWay(String userIdA, String userIdB) =>
      (blocks[userIdA]?.containsKey(userIdB) ?? false) || (blocks[userIdB]?.containsKey(userIdA) ?? false);

  RelayParty? partyByUserId(String userId) {
    for (final party in partiesByHandle.values) {
      if (party.userId == userId) return party;
    }
    return null;
  }

  int _messageCounter = 0;
  final DateTime _clockBase = DateTime.utc(2026, 4, 1, 9);

  /// How far the relay's clock runs ahead of the devices' clocks; its time
  /// reaches each client as the HTTP Date header of the key routes.
  Duration clockSkew = Duration.zero;

  DateTime now() => DateTime.now().toUtc().add(clockSkew);

  /// How far a party's device clock runs ahead of the process clock, by
  /// handle: the local clock its ServerClock corrects. Unset, a device
  /// keeps the process clock.
  final Map<String, Duration> deviceClockSkew = {};

  /// Registers [party] as the active device of its handle. A handle that
  /// already had a device moves to the new one, like a device transfer: the
  /// directory serves the new bundle and the old device's socket and client
  /// stop hearing from the relay.
  RelayParty addParty(RelayParty party) {
    partiesByHandle[party.handle] = party;
    _clientsByHandle.remove(party.handle);
    _realtimeByHandle.remove(party.handle);
    return party;
  }

  RelayConversation addDirect(String id, String handleA, String handleB) {
    return conversations[id] = RelayConversation(
      id: id,
      type: 'direct',
      memberHandles: [handleA, handleB],
      createdAt: _clockBase,
    );
  }

  /// A Sender Keys group, or with [useSenderKeys] false a legacy group whose
  /// frames go through the pairwise engine.
  RelayConversation addGroup(String id, List<String> handles, {bool useSenderKeys = true, String name = 'Group'}) {
    return conversations[id] = RelayConversation(
      id: id,
      type: 'group',
      memberHandles: List<String>.of(handles),
      createdAt: _clockBase,
      useSenderKeys: useSenderKeys,
      name: name,
    );
  }

  FakeRelayClient clientFor(String handle) =>
      _clientsByHandle.putIfAbsent(handle, () => FakeRelayClient(this, partiesByHandle[handle]!));

  FakeRelayRealtime realtimeFor(String handle) =>
      _realtimeByHandle.putIfAbsent(handle, FakeRelayRealtime.new);

  /// Appends an envelope as if a client had sent it, without going through a
  /// controller. Lets tests seed long histories cheaply.
  Map<String, dynamic> inject({
    required String senderHandle,
    required String conversationId,
    required Map<String, dynamic> envelope,
    String? clientMessageId,
  }) {
    return _accept(
      partiesByHandle[senderHandle]!,
      {
        'conversationId': conversationId,
        'clientMessageId': clientMessageId ?? 'injected-${_messageCounter + 1}',
        'envelope': envelope,
      },
      fanOut: false,
    );
  }

  Map<String, dynamic> conversationJson(RelayConversation conversation, {String? viewer}) {
    final last = conversation.messages.isEmpty ? null : conversation.messages.last;
    String listed(String handle) => listedHandles[viewer]?[handle] ?? handle;
    return {
      'id': conversation.id,
      'type': conversation.type,
      'createdAt': conversation.createdAt.toIso8601String(),
      'members': [
        for (final handle in conversation.memberHandles)
          // What the relay lists of a member (ConversationMemberSummary):
          // no name.
          {
            'userId': partiesByHandle[handle]!.userId,
            'handle': listed(handle),
          },
      ],
      'lastMessage': last,
      'useSenderKeys': conversation.useSenderKeys,
      'currentEpoch': conversation.epoch,
    };
  }

  Map<String, dynamic> _accept(
    RelayParty sender,
    Map<String, dynamic> body, {
    bool fanOut = true,
  }) {
    final conversation = conversations[body['conversationId']]!;
    final clientMessageId = body['clientMessageId'] as String;
    for (final existing in conversation.messages) {
      if (existing['clientMessageId'] == clientMessageId) {
        return existing;
      }
    }
    if (conversation.useSenderKeys && body['groupEpoch'] != conversation.epoch) {
      throw VeilApiException('stale', statusCode: 409, code: 'group_epoch_stale');
    }
    // ConversationAccessService: a block in either direction makes the peer
    // of a 1:1 unreachable for a new send; a retry of a stored one passed
    // above.
    if (conversation.type == 'direct') {
      for (final handle in conversation.memberHandles) {
        final member = partiesByHandle[handle];
        if (member != null && member.userId != sender.userId && blockedEitherWay(sender.userId, member.userId)) {
          throw VeilApiException('Peer is unreachable', statusCode: 403, code: 'peer_unreachable');
        }
      }
    }

    _messageCounter += 1;
    final envelope = body['envelope'] as Map<String, dynamic>;
    final message = <String, dynamic>{
      'id': 'srv-$_messageCounter',
      'clientMessageId': clientMessageId,
      'conversationId': conversation.id,
      'senderDeviceId': envelope['senderDeviceId'],
      'conversationOrder': conversation.messages.length + 1,
      'ciphertext': envelope['ciphertext'],
      'nonce': envelope['nonce'],
      'messageType': envelope['messageType'],
      'version': envelope['version'],
      'attachment': envelope['attachment'],
      'expiresAt': stripOuterExpiresAt ? null : envelope['expiresAt'],
      'serverReceivedAt':
          _clockBase.add(Duration(seconds: _messageCounter)).toIso8601String(),
      'deliveredAt': null,
      'readAt': null,
    };
    conversation.messages.add(message);

    if (fanOut) {
      for (final handle in conversation.memberHandles) {
        if (handle != sender.handle) {
          _deliver(handle, 'message.new', Map<String, dynamic>.of(message));
        }
        _deliver(handle, 'conversation.sync', {
          'conversationId': conversation.id,
          'reason': 'message',
        });
      }
    }
    return message;
  }

  /// GET /keys/:handle, like KeysService: the active device first, a
  /// one-time prekey claimed for each device the mode selects, and nothing
  /// claimed when a user looks up their own account.
  Map<String, dynamic> _lookup(RelayParty requester, String handle, String claim) {
    final party = partiesByHandle[handle];
    if (party == null) {
      throw VeilApiException('User not found', statusCode: 404, code: 'handle_not_found');
    }
    final active = bundleOverrides[handle] ??
        {
          ...party.bundleJson,
          if (publishedSignedPrekeys[party.deviceId] case final spk?) 'signedPrekeyBundle': spk,
        };
    Map<String, dynamic> device(Map<String, dynamic> bundle, {required bool isActive}) {
      final deviceId = bundle['deviceId'] as String;
      final claims = requester.userId != party.userId && (claim == 'all' || (claim == 'active' && isActive));
      final pool = oneTimePrekeys[deviceId];
      final prekey = claims && pool != null && pool.isNotEmpty ? pool.removeAt(0) : null;
      if (prekey != null) claimedOneTimePrekeys.putIfAbsent(deviceId, () => []).add(prekey.keyId);
      return {
        'deviceId': deviceId,
        'identityPublicKey': bundle['identityPublicKey'],
        'signedPrekeyBundle': bundle['signedPrekeyBundle'],
        'isActive': isActive,
        'oneTimePrekey': prekey == null ? null : {'keyId': prekey.keyId, 'publicKey': prekey.publicKey},
      };
    }

    return {
      'user': {'id': party.userId, 'handle': handle, 'activeDeviceId': active['deviceId']},
      'devices': [
        device(active, isActive: true),
        for (final extra in extraDevices[handle] ?? const <Map<String, dynamic>>[]) device(extra, isActive: false),
      ],
    };
  }

  /// GET /keys/group/:conversationId, like KeysService.getGroupMemberKeys:
  /// every other member's entry as GET /keys/:handle lists it, nothing
  /// claimed, and group_not_found for anyone but a member of a group.
  Map<String, dynamic> _groupKeys(RelayParty requester, String conversationId) {
    final conversation = conversations[conversationId];
    if (conversation == null || conversation.type != 'group' || !conversation.memberHandles.contains(requester.handle)) {
      throw VeilApiException('Group not found', statusCode: 404, code: 'group_not_found');
    }
    return {
      'conversationId': conversationId,
      'epoch': conversation.epoch,
      'members': [
        for (final handle in conversation.memberHandles)
          if (handle != requester.handle && partiesByHandle.containsKey(handle)) _lookup(requester, handle, 'none'),
      ],
    };
  }

  void _markRead(RelayParty reader, String messageId) {
    for (final conversation in conversations.values) {
      for (final message in conversation.messages) {
        if (message['id'] != messageId) continue;
        final now = _clockBase.add(Duration(seconds: ++_messageCounter)).toIso8601String();
        for (final handle in conversation.memberHandles) {
          _deliver(handle, 'message.delivered', {
            'messageId': messageId,
            'userId': reader.userId,
            'deliveredAt': now,
          });
          _deliver(handle, 'message.read', {
            'messageId': messageId,
            'userId': reader.userId,
            'readAt': now,
          });
        }
        return;
      }
    }
  }

  // Network delivery is asynchronous: the sender's HTTP ack and the
  // recipient's socket event race, so never deliver inside the sender's call.
  void _deliver(String handle, String event, Map<String, dynamic> payload) {
    final realtime = _realtimeByHandle[handle];
    if (realtime == null) return;
    scheduleMicrotask(() => realtime.deliver(event, payload));
  }
}

class FakeRelayClient extends VeilApiClient {
  FakeRelayClient(this.relay, this.me)
      : super(
          baseUrl: 'http://relay.invalid/v1',
          serverClock: ServerClock(
            localClock: () => DateTime.now().add(relay.deviceClockSkew[me.handle] ?? Duration.zero),
          ),
        );

  final FakeRelay relay;
  final RelayParty me;

  int conversationFetches = 0;
  int messageFetches = 0;
  int groupKeyRequests = 0;
  // While set, every send fails as an unreachable network makes it: no
  // response at all.
  bool unreachable = false;
  // While set, history fetches wait for it to complete.
  Completer<void>? messageFetchGate;
  final Map<String, int> directoryLookups = {};
  final List<String> markReadCalls = [];
  final List<String> signedPrekeyUploads = [];

  /// The stale tokens a refresh was asked for, and what it answers with:
  /// null, as without a refresher, unless a test sets [refreshTo].
  final List<String> tokenRefreshes = [];
  String? Function(String staleToken)? refreshTo;

  @override
  Future<String?> refreshAccessToken(String staleToken) async {
    tokenRefreshes.add(staleToken);
    return refreshTo?.call(staleToken);
  }

  /// While set, every list of conversations fails as an unreachable network
  /// makes it, so what the device shows is what its cache holds.
  bool failConversationFetches = false;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    conversationFetches += 1;
    if (failConversationFetches) throw VeilApiException('The server is unreachable.', code: 'network_unavailable');
    return {
      'items': [
        for (final conversation in relay.conversations.values)
          if (conversation.memberHandles.contains(me.handle))
            relay.conversationJson(conversation, viewer: me.handle),
      ],
      'nextCursor': null,
    };
  }

  /// How many times each group was asked for by id, and how many of the
  /// next answers fail as an unreachable network makes them.
  final Map<String, int> groupFetches = {};
  int failGroupFetches = 0;

  // GroupsService.getGroup: a group's name and members, for a member only.
  @override
  Future<Map<String, dynamic>> getGroup(String accessToken, String conversationId) async {
    groupFetches[conversationId] = (groupFetches[conversationId] ?? 0) + 1;
    if (failGroupFetches > 0) {
      failGroupFetches -= 1;
      throw VeilApiException('The server is unreachable.', code: 'network_unavailable');
    }
    final conversation = relay.conversations[conversationId];
    if (conversation == null || conversation.type != 'group' || !conversation.memberHandles.contains(me.handle)) {
      throw VeilApiException('Group not found', statusCode: 404, code: 'group_not_found');
    }
    final listed = relay.conversationJson(conversation, viewer: me.handle);
    return {
      'id': conversation.id,
      'type': conversation.type,
      'name': conversation.name,
      'description': null,
      'isPublic': false,
      'useSenderKeys': conversation.useSenderKeys,
      'epoch': conversation.epoch,
      'createdAt': listed['createdAt'],
      'members': [
        for (final member in (listed['members'] as List).cast<Map<String, dynamic>>())
          {'userId': member['userId'], 'handle': member['handle'], 'role': 'member'},
      ],
      'lastMessage': listed['lastMessage'],
    };
  }

  // One page holds the whole history unless the relay sets a page size: its
  // page size is its own choice, and one page keeps long-history tests
  // delivering in send order. With [FakeRelay.messagePageSize], pages are
  // cut as ConversationsService.listMessagesForUser cuts them: newest first,
  // the cursor naming the oldest message of the page before.
  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    messageFetches += 1;
    await messageFetchGate?.future;
    final messages = relay.conversations[conversationId]!.messages;
    final pageSize = relay.messagePageSize;
    if (pageSize == null) {
      return {
        'items': [for (final message in messages) Map<String, dynamic>.of(message)],
        'nextCursor': null,
      };
    }
    final before = cursor == null ? messages.length : messages.indexWhere((message) => message['id'] == cursor);
    final page = messages.sublist(before - pageSize < 0 ? 0 : before - pageSize, before).reversed.toList();
    return {
      'items': [for (final message in page) Map<String, dynamic>.of(message)],
      'nextCursor': page.length == pageSize ? page.last['id'] : null,
    };
  }

  // The key directory and prekey routes the app reaches through the
  // generic authenticated helpers (KeysApi).
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    required String? accessToken,
    Map<String, String>? query,
  }) async {
    _stampDate();
    if (path.startsWith('/keys/group/')) {
      groupKeyRequests += 1;
      return relay._groupKeys(me, Uri.decodeComponent(path.substring('/keys/group/'.length)));
    }
    if (path.startsWith('/keys/')) {
      final handle = Uri.decodeComponent(path.substring('/keys/'.length));
      directoryLookups[handle] = (directoryLookups[handle] ?? 0) + 1;
      // KeysService.getKeys: a block in either direction answers as an
      // unknown handle does, and claims nothing. The group route does not.
      final party = relay.partiesByHandle[handle];
      if (party != null && relay.blockedEitherWay(me.userId, party.userId)) {
        throw VeilApiException('User not found', statusCode: 404, code: 'handle_not_found');
      }
      return relay._lookup(me, handle, query?['claim'] ?? 'active');
    }
    if (path == '/prekeys/count') {
      return {'available': relay.oneTimePrekeys[me.deviceId]?.length ?? 0};
    }
    // UsersService.getUserByHandle: a block in either direction answers as
    // an unknown handle does.
    if (path.startsWith('/users/')) {
      final party = relay.partiesByHandle[Uri.decodeComponent(path.substring('/users/'.length))];
      if (party == null || relay.blockedEitherWay(me.userId, party.userId)) {
        throw VeilApiException('User not found', statusCode: 404, code: 'handle_not_found');
      }
      return {'id': party.userId, 'handle': party.handle, 'status': 'active'};
    }
    throw UnimplementedError('GET $path');
  }

  @override
  Future<Map<String, dynamic>> postJson(String path, {required String? accessToken, Object? body}) async {
    _stampDate();
    if (path != '/prekeys') throw UnimplementedError('POST $path');
    final pool = relay.oneTimePrekeys.putIfAbsent(me.deviceId, () => []);
    final uploaded = [
      for (final raw in ((body as Map<String, dynamic>)['prekeys'] as List).cast<Map<String, dynamic>>())
        OneTimePrekey(keyId: raw['keyId'] as int, publicKey: raw['publicKey'] as String),
    ];
    pool.addAll(uploaded);
    return {'uploaded': uploaded.length, 'available': pool.length};
  }

  // KeysService.rotateSignedPrekey: a v2 bundle signed by the device
  // identity, its timestamp within the last hour and at most ten minutes
  // ahead of the relay's clock, the same IKx, and a higher spkId than the
  // bundle served now.
  @override
  Future<Map<String, dynamic>> putJson(String path, {required String? accessToken, Object? body}) async {
    _stampDate();
    if (path != '/keys/signed-prekey') throw UnimplementedError('PUT $path');
    final bundle = (body as Map<String, dynamic>)['signedPrekeyBundle'] as String;
    final now = relay.now();
    final RemotePrekeyBundle next;
    try {
      next = await verifyRemoteBundle(bundle, me.identity.identityPublicKey);
    } catch (_) {
      throw VeilApiException('not signed by the device', statusCode: 400, code: 'invalid_device_signature');
    }
    if (next is! PrekeyBundleV2) {
      throw VeilApiException('not a v2 bundle', statusCode: 400, code: 'validation_failed');
    }
    final spkTs = next.spkTimestampMs;
    final nowMs = now.millisecondsSinceEpoch;
    if (spkTs < nowMs - const Duration(hours: 1).inMilliseconds ||
        spkTs > nowMs + const Duration(minutes: 10).inMilliseconds) {
      throw VeilApiException('stale timestamp', statusCode: 400, code: 'signed_prekey_timestamp_out_of_window');
    }
    final served = await verifyRemoteBundle(
      relay.publishedSignedPrekeys[me.deviceId] ?? me.identity.signedPrekeyBundle,
      me.identity.identityPublicKey,
    );
    if (served is PrekeyBundleV2 && (!_sameBytes(next.ikx, served.ikx) || next.spkId <= served.spkId)) {
      throw VeilApiException('spkId must increase', statusCode: 400, code: 'validation_failed');
    }
    relay.publishedSignedPrekeys[me.deviceId] = bundle;
    signedPrekeyUploads.add(bundle);
    return {'deviceId': me.deviceId, 'spkId': next.spkId};
  }

  // The relay's time, as the HTTP Date header of each response carries it.
  void _stampDate() => serverClock.observe(HttpDate.format(relay.now()));

  static bool _sameBytes(List<int> a, List<int> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  @override
  Future<Map<String, dynamic>> sendMessage(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    if (unreachable) throw VeilApiException('The server is unreachable.', code: 'network_unavailable');
    final stored = relay._accept(me, body);
    return {'message': relay.rewriteAck?.call(Map<String, dynamic>.of(stored)) ?? stored, 'idempotent': false};
  }

  // The safety routes, as SafetyService answers them.

  // The handle the relay lists [handle]'s account under to this party.
  String _listed(String handle) => relay.listedHandles[me.handle]?[handle] ?? handle;

  @override
  Future<Map<String, dynamic>> listBlockedUsers(String accessToken) async {
    final blocked = relay.blocks[me.userId] ?? const <String, DateTime>{};
    return {
      'items': [
        for (final MapEntry(key: userId, value: at) in blocked.entries.toList().reversed)
          {
            'userId': userId,
            'handle': _listed(relay.partyByUserId(userId)?.handle ?? ''),
            'blockedAt': at.toIso8601String(),
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> blockUser(String accessToken, String userId) async {
    if (userId == me.userId) throw VeilApiException('Cannot block yourself', statusCode: 400, code: 'validation_failed');
    final target = relay.partyByUserId(userId) ??
        (throw VeilApiException('User not found', statusCode: 404, code: 'not_found'));
    final at = relay.blocks.putIfAbsent(me.userId, () => {}).putIfAbsent(userId, relay.now);
    return {
      'blocked': {'userId': userId, 'handle': _listed(target.handle), 'blockedAt': at.toIso8601String()},
    };
  }

  @override
  Future<Map<String, dynamic>> unblockUser(String accessToken, String userId) async {
    relay.blocks[me.userId]?.remove(userId);
    return {'userId': userId, 'unblocked': true};
  }

  @override
  Future<Map<String, dynamic>> setConversationMute(
    String accessToken,
    String conversationId, {
    int? mutedForSeconds,
    required bool unmute,
  }) async {
    final conversation = relay.conversations[conversationId];
    if (conversation == null || !conversation.memberHandles.contains(me.handle)) {
      throw VeilApiException('Conversation membership required', statusCode: 403, code: 'conversation_membership_required');
    }
    final mine = relay.mutes.putIfAbsent(me.userId, () => {});
    if (unmute) {
      mine.remove(conversationId);
      return {'mute': null};
    }
    mine[conversationId] = mutedForSeconds;
    final until = mutedForSeconds == null ? null : relay.now().add(Duration(seconds: mutedForSeconds));
    return {
      'mute': {'conversationId': conversationId, 'mutedUntil': until?.toIso8601String()},
    };
  }

  /// Records which fields the client passed: the ones fileAbuseReport puts
  /// in the request body.
  @override
  Future<Map<String, dynamic>> fileAbuseReport(
    String accessToken, {
    required String reportedUserId,
    required String reason,
    String? conversationId,
    String? messageId,
  }) async {
    await relay.reportGate?.future;
    if (relay.refuseReports > 0) {
      relay.refuseReports -= 1;
      throw VeilApiException('Too many requests', statusCode: 429, code: 'rate_limited');
    }
    if (reportedUserId == me.userId) {
      throw VeilApiException('Cannot report yourself', statusCode: 400, code: 'validation_failed');
    }
    if (relay.partyByUserId(reportedUserId) == null) {
      throw VeilApiException('Reported user not found', statusCode: 404, code: 'not_found');
    }
    if (conversationId != null && !(relay.conversations[conversationId]?.memberHandles.contains(me.handle) ?? false)) {
      throw VeilApiException('Conversation membership required', statusCode: 403, code: 'conversation_membership_required');
    }
    relay.reports.add((
      reporterUserId: me.userId,
      fields: {
        'reportedUserId': reportedUserId,
        'reason': reason,
        if (conversationId != null) 'conversationId': conversationId,
        if (messageId != null) 'messageId': messageId,
      },
    ));
    return {'reportId': 'report-${relay.reports.length}', 'filedAt': relay.now().toIso8601String()};
  }

  @override
  Future<Map<String, dynamic>> markRead(String accessToken, String messageId) async {
    markReadCalls.add(messageId);
    relay._markRead(me, messageId);
    return {'messageId': messageId};
  }

  // AttachmentsService.createUploadTicket for a proposed id, which the app
  // always sends: a new id is taken as is; the uploader's own row that is
  // not uploaded yet is re-issued for the same ciphertext; anything else is
  // a conflict.
  @override
  Future<Map<String, dynamic>> createUploadTicket(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    final attachmentId = body['attachmentId'];
    if (attachmentId is! String || !_uuidV4.hasMatch(attachmentId)) {
      throw VeilApiException('attachmentId must be a UUID v4', statusCode: 400, code: 'validation_failed');
    }
    final existing = relay.attachments[attachmentId];
    if (existing != null &&
        (existing.uploaderDeviceId != me.deviceId ||
            existing.uploadStatus == 'uploaded' ||
            existing.sha256.toLowerCase() != (body['sha256'] as String).toLowerCase() ||
            existing.sizeBytes != body['sizeBytes'])) {
      throw VeilApiException('taken', statusCode: 409, code: 'attachment_id_conflict');
    }
    relay.attachments[attachmentId] = RelayAttachment(
      uploaderDeviceId: me.deviceId,
      sha256: body['sha256'] as String,
      sizeBytes: body['sizeBytes'] as int,
    );
    relay.uploadTickets.add(attachmentId);
    relay.uploadTicketContentTypes.add(body['contentType']);
    return {
      'attachmentId': attachmentId,
      'upload': {
        'storageKey': 'attachments/$attachmentId/blob',
        'uploadUrl': 'https://upload.invalid/$attachmentId',
        'headers': {'x-amz-meta-sha256': body['sha256']},
        'expiresAt': DateTime.now().add(relay.uploadTicketLifetime).toUtc().toIso8601String(),
      },
    };
  }

  @override
  Future<void> uploadEncryptedBlobFile({
    required String uploadUrl,
    required Map<String, dynamic> headers,
    required dynamic file,
    void Function(int sentBytes, int totalBytes)? onProgress,
    AttachmentUploadCancellationSignal? cancellationSignal,
  }) async {
    final bytes = await (file as File).readAsBytes();
    relay.uploadedBlobs[uploadUrl.split('/').last] = bytes;
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<Map<String, dynamic>> completeUpload(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    final attachmentId = body['attachmentId'] as String;
    final status = body['uploadStatus'] as String;
    if (status == 'uploaded' && relay.failUploadCompletions > 0) {
      relay.failUploadCompletions -= 1;
      throw VeilApiException('relay unavailable', statusCode: 503);
    }
    relay.attachments[attachmentId]!.uploadStatus = status;
    if (status == 'failed') {
      relay.uploadedBlobs.remove(attachmentId);
    }
    return {'attachmentId': attachmentId, 'uploadStatus': status};
  }

  @override
  Future<Map<String, dynamic>> distributeGroupKeys(
    String accessToken,
    String conversationId, {
    required int epoch,
    required List<Map<String, dynamic>> distributions,
  }) async {
    for (final distribution in distributions) {
      relay.groupDistributions
          .putIfAbsent(distribution['recipientUserId'] as String, () => [])
          .add({
        'conversationId': conversationId,
        'epoch': epoch,
        'fromUserId': me.userId,
        'fromDeviceId': me.deviceId,
        'recipientDeviceId': distribution['recipientDeviceId'],
        'encryptedChainKey': distribution['encryptedChainKey'],
        'nonce': distribution['nonce'],
        'version': distribution['version'],
        'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
      });
    }
    return {
      'conversationId': conversationId,
      'epoch': epoch,
      'accepted': distributions.length,
      'expiresInSeconds': 1800,
    };
  }

  @override
  Future<Map<String, dynamic>> getGroupKeyDistributions(
    String accessToken,
    String conversationId,
  ) async {
    final epoch = relay.conversations[conversationId]!.epoch;
    return {
      'conversationId': conversationId,
      'epoch': epoch,
      'distributions': [
        for (final blob in relay.groupDistributions[me.userId] ?? const <Map<String, dynamic>>[])
          if (blob['conversationId'] == conversationId &&
              blob['epoch'] == epoch &&
              (blob['recipientDeviceId'] == null || blob['recipientDeviceId'] == me.deviceId))
            blob,
      ],
    };
  }
}

class FakeRelayRealtime extends RealtimeService {
  void Function(String event, dynamic payload)? _onEvent;
  void Function(bool connected)? _onConnectionChanged;
  bool _connected = false;
  int connectCount = 0;
  String? lastAccessToken;
  final List<String> emittedEvents = [];

  @override
  bool get isConnected => _connected;

  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    connectCount += 1;
    lastAccessToken = accessToken;
    _onEvent = onEvent;
    _onConnectionChanged = onConnectionChanged;
    _connected = true;
    onConnectionChanged?.call(true);
  }

  @override
  void disconnect() {
    if (!_connected) return;
    _connected = false;
    final callback = _onConnectionChanged;
    _onEvent = null;
    _onConnectionChanged = null;
    callback?.call(false);
  }

  @override
  void emit(String event, Map<String, dynamic> payload) {
    emittedEvents.add(event);
  }

  int authUpdates = 0;

  /// A token rotation reconnects the same socket with the new token.
  @override
  void updateAuth(String token) {
    authUpdates += 1;
    final onEvent = _onEvent;
    if (onEvent == null) return;
    final onConnectionChanged = _onConnectionChanged;
    disconnect();
    connect(baseUrl: '', accessToken: token, onEvent: onEvent, onConnectionChanged: onConnectionChanged);
  }

  /// What the relay does when the socket's access token expires: it closes
  /// the socket itself, and socket.io does not reconnect after that.
  void serverDisconnect() {
    disconnect();
    onServerDisconnect?.call();
  }

  /// Server-to-client push. Dropped while disconnected, like a real socket.
  void deliver(String event, Map<String, dynamic> payload) {
    final handler = _onEvent;
    if (!_connected || handler == null) return;
    handler(event, payload);
  }
}
