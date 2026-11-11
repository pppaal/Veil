import 'dart:convert';

import 'identity_key_value_backend.dart';
import 'trusted_identity.dart';

/// Persists the identity pin table as one versioned JSON document.
///
/// Decoding fails closed: a document that is unreadable or has an unknown
/// version throws [FormatException] instead of reading as "no pins", which
/// would silently turn every key change into a first use.
class TrustedIdentityStore {
  TrustedIdentityStore(this._backend);

  /// Relative to the backend's own namespace (SecureScope.identity).
  static const String storageKey = 'pins.v1';
  static const int _schemaVersion = 1;

  final IdentityKeyValueBackend _backend;

  Future<List<TrustedIdentity>> load() async {
    final raw = await _backend.read(storageKey);
    if (raw == null) return <TrustedIdentity>[];
    final document = json.decode(raw);
    if (document is! Map || document['v'] != _schemaVersion || document['pins'] is! List) {
      throw const FormatException('identity pin table has an unknown format');
    }
    return [
      for (final pin in document['pins'] as List)
        if (pin is Map<String, dynamic>)
          TrustedIdentity.fromJson(pin)
        else
          throw const FormatException('identity pin table holds a malformed pin'),
    ];
  }

  Future<void> save(List<TrustedIdentity> pins) => _backend.write(
        storageKey,
        json.encode({
          'v': _schemaVersion,
          'pins': [for (final pin in pins) pin.toJson()],
        }),
      );

  /// Forgets every pin (device wipe).
  Future<void> clear() => _backend.delete(storageKey);
}
