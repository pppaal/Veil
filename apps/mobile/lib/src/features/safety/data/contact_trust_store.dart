import 'dart:convert';

import '../../../core/identity/identity_key_value_backend.dart';

/// What this phone recorded about one chat (ContactTrust): times are
/// milliseconds since the epoch, 0 meaning "before this phone kept trust
/// records" (the baseline). Fields this build does not know are kept.
class ChatTrustRecord {
  ChatTrustRecord._(this._json);

  /// A chat first seen at [seen].
  factory ChatTrustRecord.seen(int seen) => ChatTrustRecord._({'seen': seen, 'accepted': null, 'sent': null, 'gone': null});

  /// A chat the baseline found: accepted, and [mine0] when it held a message
  /// of mine then.
  factory ChatTrustRecord.baseline({required bool mine0}) =>
      ChatTrustRecord._({'seen': 0, 'accepted': 0, 'sent': null, if (mine0) 'mine0': true, 'gone': null});

  final Map<String, dynamic> _json;

  int get seen => _int('seen') ?? 0;
  int? get accepted => _int('accepted');
  set accepted(int? value) => _json['accepted'] = value;
  int? get sent => _int('sent');
  set sent(int? value) => _json['sent'] = value;
  int? get gone => _int('gone');
  set gone(int? value) => _json['gone'] = value;

  /// Started from a handle the user typed (ContactTrust.startDirect).
  bool get typed => _json['typed'] == true;
  set typed(bool value) => value ? _json['typed'] = true : _json.remove('typed');

  /// A group this phone created (ContactTrust.acceptCreated).
  bool get created => _json['created'] == true;
  set created(bool value) => value ? _json['created'] = true : _json.remove('created');

  /// Held a message of mine when the baseline ran.
  bool get mine0 => _json['mine0'] == true;

  int? _int(String key) => switch (_json[key]) { final int value => value, _ => null };

  Map<String, dynamic> toJson() => _json;
}

/// The trust document, `contact_trust.v1`: a record per chat, when new
/// devices were admitted, when nicknames were first seen, the claim banners
/// shown and the verify nudge counts. Unknown fields are kept on rewrite.
class ContactTrustDocument {
  ContactTrustDocument._(this._json, this.chats, this.changed, this.named, this.claims, this.nudges);

  /// No document: the baseline is pending.
  factory ContactTrustDocument.empty() => ContactTrustDocument._({'v': 1, 'baseline': false}, {}, {}, {}, {}, {});

  /// Throws [FormatException] on a document of the wrong shape.
  factory ContactTrustDocument.fromJson(Map<String, dynamic> json) {
    Map<String, int> times(String key) {
      final raw = json[key];
      if (raw == null) return {};
      if (raw is! Map<String, dynamic>) throw FormatException('$key is not an object');
      final times = <String, int>{};
      for (final MapEntry(key: id, :value) in raw.entries) {
        if (value is! int) throw FormatException('$key holds a non-number');
        times[id] = value;
      }
      return times;
    }

    final rawChats = json['chats'] ?? <String, dynamic>{};
    if (rawChats is! Map<String, dynamic>) throw const FormatException('chats is not an object');
    final chats = <String, ChatTrustRecord>{};
    for (final MapEntry(:key, :value) in rawChats.entries) {
      if (value is! Map<String, dynamic> || value['seen'] is! int) throw const FormatException('bad chat record');
      chats[key] = ChatTrustRecord._(Map<String, dynamic>.of(value));
    }
    if (json['v'] != 1 || json['baseline'] is! bool) throw const FormatException('not a v1 trust document');
    return ContactTrustDocument._(
      Map<String, dynamic>.of(json),
      chats,
      times('changed'),
      times('named'),
      times('claims'),
      times('nudges'),
    );
  }

  final Map<String, dynamic> _json;
  final Map<String, ChatTrustRecord> chats;

  /// When a new device of each account was admitted.
  final Map<String, int> changed;

  /// When this phone first saw a nickname on each handle (lower case).
  final Map<String, int> named;

  /// When the claim banner first showed in each chat.
  final Map<String, int> claims;

  /// How many chat openings showed the verify nudge, by account; -1 once
  /// the user verified.
  final Map<String, int> nudges;

  bool get baseline => _json['baseline'] == true;
  set baseline(bool value) => _json['baseline'] = value;

  Map<String, dynamic> toJson() => {
        ..._json,
        'v': 1,
        'chats': {for (final MapEntry(:key, :value) in chats.entries) key: value.toJson()},
        'changed': changed,
        'named': named,
        'claims': claims,
        'nudges': nudges,
      };
}

/// Keeps the trust document in the keystore (SecureScope.conversationPolicy),
/// so it survives a cache wipe and is wiped with the scope at sign-out.
class ContactTrustStore {
  ContactTrustStore(this._store);

  static const documentKey = 'contact_trust.v1';

  final IdentityKeyValueBackend _store;

  /// The stored document; null when there is none or it does not parse (a
  /// corrupt document counts as missing, so the baseline runs again). A
  /// keystore that cannot be read throws.
  Future<ContactTrustDocument?> read() async {
    final raw = await _store.read(documentKey);
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ContactTrustDocument.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(ContactTrustDocument document) => _store.write(documentKey, json.encode(document.toJson()));
}
