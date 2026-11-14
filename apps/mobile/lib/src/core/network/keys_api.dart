import '../crypto/crypto_engine.dart';
import 'veil_api_client.dart';

/// Which devices of the target get a one-time prekey claimed by a lookup.
enum KeyClaim {
  /// Only the user's active device: the device a 1:1 session is opened to.
  active,

  /// Identity and signed prekeys only; nothing is consumed.
  none,
}

/// One trusted device as the directory lists it.
class DirectoryDevice {
  const DirectoryDevice({required this.bundle, required this.isActive, this.oneTimePrekey});

  final KeyBundle bundle;

  /// The device that represents the user right now.
  final bool isActive;

  /// Claimed for this lookup; spent by the server whether or not the caller
  /// uses it. Null when the claim mode did not select the device, the pool
  /// is empty, or a claim budget is spent.
  final OneTimePrekey? oneTimePrekey;
}

/// A user's entry in the authenticated key directory.
class KeyDirectoryEntry {
  const KeyDirectoryEntry({
    required this.userId,
    required this.handle,
    required this.activeDeviceId,
    required this.devices,
  });

  final String userId;
  final String handle;
  final String activeDeviceId;
  final List<DirectoryDevice> devices;

  /// The active device, provided the directory also lists it. There is no
  /// fallback to another device: the server must not get to pick which of
  /// a user's devices a session or a chain key goes to.
  DirectoryDevice? get activeDevice => device(activeDeviceId);

  DirectoryDevice? device(String deviceId) =>
      devices.where((candidate) => candidate.bundle.deviceId == deviceId).firstOrNull;
}

/// The other members of a group in the key directory, as of [epoch].
class GroupMemberKeys {
  const GroupMemberKeys({required this.conversationId, required this.epoch, required this.members});

  final String conversationId;
  final int epoch;

  /// By user id. A member without a trusted active device is not listed.
  final Map<String, KeyDirectoryEntry> members;
}

/// Authenticated key directory and this device's prekey uploads
/// (GET /keys/:handle, POST /prekeys, GET /prekeys/count,
/// PUT /keys/signed-prekey). Every call is tied to the device's session, so
/// the server can hold each requester to its claim budgets.
class KeysApi {
  KeysApi(this._client, this._codec);

  final VeilApiClient _client;
  final KeyBundleCodec _codec;

  /// The directory's time, as its responses report it.
  ServerClock get serverClock => _client.serverClock;

  /// Looks [handle] up. Throws [FormatException] when the answer does not
  /// have the directory's shape: it is relayed by the server and decides
  /// whom this device encrypts to, so nothing in it is guessed.
  Future<KeyDirectoryEntry> lookup(
    String handle, {
    required String? accessToken,
    KeyClaim claim = KeyClaim.active,
  }) async {
    final response = await _client.getJson(
      '/keys/${Uri.encodeComponent(handle)}',
      accessToken: accessToken,
      query: {'claim': claim.name},
    );
    return _entry(response);
  }

  /// Every other member's entry for the group [conversationId] in one
  /// request (GET /keys/group/:conversationId), as of the epoch it names.
  /// Nothing is claimed. A member without a trusted active device is left
  /// out, and so is one whose entry is malformed: it vouches for none of
  /// that member's devices, and must not cost the others theirs. Throws
  /// [FormatException] for an answer of the wrong shape or about another
  /// conversation.
  Future<GroupMemberKeys> groupMemberKeys(String conversationId, {required String? accessToken}) async {
    final response = await _client.getJson(
      '/keys/group/${Uri.encodeComponent(conversationId)}',
      accessToken: accessToken,
    );
    if (response['conversationId'] != conversationId) {
      throw const FormatException('group keys: answer is about another conversation');
    }
    final epoch = response['epoch'];
    final members = response['members'];
    if (epoch is! int || epoch < 0) throw const FormatException('group keys: bad epoch');
    if (members is! List) throw const FormatException('group keys: members is not a list');
    final entries = <KeyDirectoryEntry>[];
    for (final raw in members) {
      try {
        entries.add(_entry(_object(raw, 'member')));
      } on FormatException {
        continue;
      }
    }
    return GroupMemberKeys(
      conversationId: conversationId,
      epoch: epoch,
      members: {for (final entry in entries) entry.userId: entry},
    );
  }

  KeyDirectoryEntry _entry(Map<String, dynamic> response) {
    final user = _object(response['user'], 'user');
    final userId = _text(user, 'id');
    final userHandle = _text(user, 'handle');
    final devices = response['devices'];
    if (devices is! List) throw const FormatException('key directory: devices is not a list');
    return KeyDirectoryEntry(
      userId: userId,
      handle: userHandle,
      activeDeviceId: _text(user, 'activeDeviceId'),
      devices: [
        for (final raw in devices) _device(_object(raw, 'device'), userId: userId, handle: userHandle),
      ],
    );
  }

  /// Publishes one-time prekeys; returns how many the server now holds.
  Future<int> uploadOneTimePrekeys(List<OneTimePrekey> prekeys, {required String? accessToken}) async {
    final response = await _client.postJson(
      '/prekeys',
      accessToken: accessToken,
      body: {
        'prekeys': [
          for (final prekey in prekeys) {'keyId': prekey.keyId, 'publicKey': prekey.publicKey},
        ],
      },
    );
    return _count(response, 'available');
  }

  /// How many of this device's one-time prekeys are still unclaimed.
  Future<int> oneTimePrekeyCount({required String? accessToken}) async =>
      _count(await _client.getJson('/prekeys/count', accessToken: accessToken), 'available');

  /// Replaces this device's published signed prekey.
  Future<void> rotateSignedPrekey(String signedPrekeyBundle, {required String? accessToken}) =>
      _client.putJson(
        '/keys/signed-prekey',
        accessToken: accessToken,
        body: {'signedPrekeyBundle': signedPrekeyBundle},
      );

  DirectoryDevice _device(Map<String, dynamic> raw, {required String userId, required String handle}) {
    final isActive = raw['isActive'];
    if (isActive is! bool) throw const FormatException('key directory: isActive is not a bool');
    final bundle = _codec.decodeDirectoryBundle({
      'userId': userId,
      'handle': handle,
      'deviceId': _text(raw, 'deviceId'),
      'identityPublicKey': _text(raw, 'identityPublicKey'),
      'signedPrekeyBundle': _text(raw, 'signedPrekeyBundle'),
    });
    final prekey = raw['oneTimePrekey'];
    return DirectoryDevice(
      bundle: bundle,
      isActive: isActive,
      oneTimePrekey: prekey == null ? null : _oneTimePrekey(_object(prekey, 'oneTimePrekey')),
    );
  }

  static OneTimePrekey _oneTimePrekey(Map<String, dynamic> raw) {
    final keyId = raw['keyId'];
    if (keyId is! int || keyId < 0) throw const FormatException('key directory: bad one-time prekey id');
    return OneTimePrekey(keyId: keyId, publicKey: _text(raw, 'publicKey'));
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('key directory: $field is not an object');
  }

  static String _text(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('key directory: $field is missing');
  }

  static int _count(Map<String, dynamic> response, String field) {
    final value = response[field];
    if (value is int && value >= 0) return value;
    throw FormatException('prekeys: $field is not a count');
  }
}
