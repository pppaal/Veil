import 'trusted_identity.dart';

/// What [TrustedIdentityResolver.evaluate] concluded about a directory
/// identity key for one (userId, deviceId).
sealed class IdentityVerdict {
  const IdentityVerdict();

  /// True when the key may be used without asking the user: it was just
  /// pinned on first use, or it matches the pin. Every other verdict needs an
  /// explicit user decision.
  bool get isTrusted;
}

/// No pin existed for this user at all; the key is pinned now.
final class FirstUse extends IdentityVerdict {
  const FirstUse(this.pin);

  final TrustedIdentity pin;

  @override
  bool get isTrusted => true;
}

/// The key equals the pin.
final class PinMatch extends IdentityVerdict {
  const PinMatch(this.pin);

  final TrustedIdentity pin;

  @override
  bool get isTrusted => true;
}

/// The user is known but this device is not. Nothing is pinned until the
/// user approves the device.
final class NewDeviceForKnownUser extends IdentityVerdict {
  const NewDeviceForKnownUser({required this.knownUserVerified});

  /// Whether any of the user's pinned devices was verified out of band, in
  /// which case the new device must never be accepted silently.
  final bool knownUserVerified;

  @override
  bool get isTrusted => false;
}

/// The device id is pinned under another user. A device belongs to one
/// account, so the directory misattributes one of the two; nothing is pinned,
/// and no approval can resolve it.
final class DeviceOfAnotherUser extends IdentityVerdict {
  const DeviceOfAnotherUser(this.pinned);

  final TrustedIdentity pinned;

  @override
  bool get isTrusted => false;
}

/// The device presented a different key than its unverified pin.
final class KeyChanged extends IdentityVerdict {
  const KeyChanged({required this.pinned, required this.presentedKey});

  final TrustedIdentity pinned;
  final String presentedKey;

  @override
  bool get isTrusted => false;
}

/// The device presented a different key than a pin the user had verified.
final class KeyChangedVerified extends IdentityVerdict {
  const KeyChangedVerified({required this.pinned, required this.presentedKey});

  final TrustedIdentity pinned;
  final String presentedKey;

  @override
  bool get isTrusted => false;
}
