import 'dart:typed_data';

import '../util/base64url.dart';
import '../util/keyed_async_lock.dart';
import 'identity_verdict.dart';
import 'trusted_identity.dart';
import 'trusted_identity_store.dart';

/// Trust-on-first-use policy over the pin table: the single place that
/// decides whether a directory identity key may be used.
///
/// A key is pinned silently only the first time a user is ever seen. A new
/// device of a known user, or a different key for a pinned device, is never
/// accepted automatically; the user must [approve] it. Every operation runs
/// under one lock, so concurrent evaluations cannot both "first use" a device
/// or lose each other's writes.
class TrustedIdentityResolver {
  TrustedIdentityResolver({required TrustedIdentityStore store, DateTime Function()? clock})
      : _store = store,
        _clock = clock ?? DateTime.now;

  final TrustedIdentityStore _store;
  final DateTime Function() _clock;
  final KeyedAsyncLock<String> _lock = KeyedAsyncLock<String>();

  DateTime _now() => _clock().toUtc();

  /// Classifies [identityKey] (base64url) for the device. Pins it when the
  /// user has never been seen before; changes nothing otherwise, except that
  /// with [admitNewDeviceOfUnverifiedUser] a new device of a user none of
  /// whose devices is verified is pinned as approved in the same step
  /// ([NewDeviceForKnownUser.admitted]). Deciding and pinning under one lock
  /// keeps two keys presented at once for one new device from both passing.
  Future<IdentityVerdict> evaluate(
    String userId,
    String deviceId,
    String identityKey, {
    bool admitNewDeviceOfUnverifiedUser = false,
  }) async {
    _requireAddress(userId, deviceId);
    final key = _canonicalKey(identityKey);
    return _locked((pins) async {
      // Group chains are keyed by device id alone, so the same id under a
      // second user would let that user take over the first one's chain.
      final elsewhere = pins.where((p) => p.deviceId == deviceId && p.userId != userId).firstOrNull;
      if (elsewhere != null) return DeviceOfAnotherUser(elsewhere);
      final pin = _pinIn(pins, userId, deviceId);
      if (pin != null) {
        if (pin.identityKey == key) return PinMatch(pin);
        return pin.isVerified
            ? KeyChangedVerified(pinned: pin, presentedKey: key)
            : KeyChanged(pinned: pin, presentedKey: key);
      }
      final knownDevices = pins.where((p) => p.userId == userId);
      if (knownDevices.isNotEmpty) {
        final verified = knownDevices.any((p) => p.isVerified);
        if (verified || !admitNewDeviceOfUnverifiedUser) return NewDeviceForKnownUser(knownUserVerified: verified);
        final now = _now();
        final admitted = TrustedIdentity(
          userId: userId,
          deviceId: deviceId,
          identityKey: key,
          firstSeenAt: now,
          approvedAt: now,
        );
        await _store.save([...pins, admitted]);
        return NewDeviceForKnownUser(knownUserVerified: false, admitted: admitted);
      }
      final pinned = TrustedIdentity(
        userId: userId,
        deviceId: deviceId,
        identityKey: key,
        firstSeenAt: _now(),
      );
      await _store.save([...pins, pinned]);
      return FirstUse(pinned);
    });
  }

  /// The user accepted [identityKey] for the device: it replaces any earlier
  /// pin, and any verification of the earlier key no longer applies.
  Future<TrustedIdentity> approve(String userId, String deviceId, String identityKey) async {
    _requireAddress(userId, deviceId);
    final key = _canonicalKey(identityKey);
    return _locked((pins) async {
      final now = _now();
      final approved = TrustedIdentity(
        userId: userId,
        deviceId: deviceId,
        identityKey: key,
        firstSeenAt: now,
        approvedAt: now,
      );
      await _store.save([..._othersThan(pins, userId, deviceId), approved]);
      return approved;
    });
  }

  /// Records that the user verified [identityKey] out of band. Throws
  /// [StateError] unless it is exactly the pinned key: verification must
  /// never double as approval of a changed key.
  Future<TrustedIdentity> markVerified(String userId, String deviceId, String identityKey) async {
    _requireAddress(userId, deviceId);
    final key = _canonicalKey(identityKey);
    return _locked((pins) async {
      final pin = _pinIn(pins, userId, deviceId);
      if (pin == null || pin.identityKey != key) {
        throw StateError('only the pinned identity key can be marked verified');
      }
      final verified = pin.verifiedOn(_now());
      await _store.save([..._othersThan(pins, userId, deviceId), verified]);
      return verified;
    });
  }

  /// Imports a verification recorded before the pin table existed: pins
  /// [identityKey] as verified at [verifiedAt] when the device has no pin
  /// yet or pins exactly this key. A different pin is left alone, because a
  /// verification never replaces a key.
  Future<void> adoptVerified(String userId, String deviceId, String identityKey, {required DateTime verifiedAt}) async {
    _requireAddress(userId, deviceId);
    final key = _canonicalKey(identityKey);
    await _locked((pins) async {
      final pin = _pinIn(pins, userId, deviceId);
      if (pin != null && pin.identityKey != key) return;
      final verified = (pin ??
              TrustedIdentity(userId: userId, deviceId: deviceId, identityKey: key, firstSeenAt: verifiedAt.toUtc()))
          .verifiedOn(verifiedAt.toUtc());
      await _store.save([..._othersThan(pins, userId, deviceId), verified]);
    });
  }

  Future<TrustedIdentity?> pinFor(String userId, String deviceId) =>
      _locked((pins) async => _pinIn(pins, userId, deviceId));

  Future<List<TrustedIdentity>> pinsForUser(String userId) =>
      _locked((pins) async => pins.where((p) => p.userId == userId).toList(growable: false));

  /// Runs [body] on the current pin table with every other operation held off.
  Future<T> _locked<T>(Future<T> Function(List<TrustedIdentity> pins) body) =>
      _lock.synchronized(TrustedIdentityStore.storageKey, () async => body(await _store.load()));

  static void _requireAddress(String userId, String deviceId) {
    if (userId.isEmpty || deviceId.isEmpty) {
      throw ArgumentError('userId and deviceId must be non-empty');
    }
  }

  static TrustedIdentity? _pinIn(List<TrustedIdentity> pins, String userId, String deviceId) =>
      pins.where((p) => p.userId == userId && p.deviceId == deviceId).firstOrNull;

  static Iterable<TrustedIdentity> _othersThan(
    List<TrustedIdentity> pins,
    String userId,
    String deviceId,
  ) =>
      pins.where((p) => p.userId != userId || p.deviceId != deviceId);

  /// Keys arrive from several codecs; comparing decoded bytes re-encoded one
  /// way keeps padding or alphabet differences from reading as a key change.
  static String _canonicalKey(String identityKey) {
    final Uint8List bytes;
    try {
      bytes = base64UrlNoPadDecode(identityKey);
    } on FormatException {
      throw ArgumentError('identity key is not base64url');
    }
    if (bytes.isEmpty) throw ArgumentError('identity key must be non-empty');
    return base64UrlNoPadEncode(bytes);
  }
}
