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
/// user approves the device, unless the caller asked for a new device of an
/// unverified user to be admitted (see TrustedIdentityResolver.evaluate).
/// Also the verdict for a device pinned unverified while another device of
/// the user is verified: it was never compared, so it counts as new.
final class NewDeviceForKnownUser extends IdentityVerdict {
  const NewDeviceForKnownUser({required this.knownUserVerified, this.admitted});

  /// Whether any of the user's pinned devices was verified out of band, in
  /// which case the new device must never be accepted silently.
  final bool knownUserVerified;

  /// The pin this evaluation wrote for the device, when it admitted it.
  final TrustedIdentity? admitted;

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

/// The device presented a different key than its pin, and the user has
/// verified none of their devices.
final class KeyChanged extends IdentityVerdict {
  const KeyChanged({required this.pinned, required this.presentedKey});

  final TrustedIdentity pinned;
  final String presentedKey;

  @override
  bool get isTrusted => false;
}

/// The device presented a different key than its pin, and the user had
/// verified that pin or another device of the same user: accepting it takes
/// a re-verification, or the new key would be held again right after.
final class KeyChangedVerified extends IdentityVerdict {
  const KeyChangedVerified({required this.pinned, required this.presentedKey});

  final TrustedIdentity pinned;
  final String presentedKey;

  @override
  bool get isTrusted => false;
}
