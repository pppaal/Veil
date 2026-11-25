/// A contact device's identity key as pinned on this device (trust on first
/// use). Every crypto consumer compares directory keys against this pin
/// instead of trusting whatever the server returns.
class TrustedIdentity {
  const TrustedIdentity({
    required this.userId,
    required this.deviceId,
    required this.identityKey,
    required this.firstSeenAt,
    this.verifiedAt,
    this.approvedAt,
  });

  final String userId;
  final String deviceId;

  /// The identity public key, as canonical unpadded base64url.
  final String identityKey;

  /// When this key was pinned for the device.
  final DateTime firstSeenAt;

  /// When the user confirmed this exact key out of band (safety number or QR).
  final DateTime? verifiedAt;

  /// When the user explicitly accepted this key, replacing an earlier pin or
  /// admitting a new device of a known contact.
  final DateTime? approvedAt;

  bool get isVerified => verifiedAt != null;

  TrustedIdentity verifiedOn(DateTime at) => TrustedIdentity(
        userId: userId,
        deviceId: deviceId,
        identityKey: identityKey,
        firstSeenAt: firstSeenAt,
        verifiedAt: at,
        approvedAt: approvedAt,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'deviceId': deviceId,
        'identityKey': identityKey,
        'firstSeenAtMs': firstSeenAt.millisecondsSinceEpoch,
        if (verifiedAt != null) 'verifiedAtMs': verifiedAt!.millisecondsSinceEpoch,
        if (approvedAt != null) 'approvedAtMs': approvedAt!.millisecondsSinceEpoch,
      };

  /// Throws [FormatException] on any field of the wrong shape.
  factory TrustedIdentity.fromJson(Map<String, dynamic> json) {
    String text(String field) {
      final value = json[field];
      if (value is String && value.isNotEmpty) return value;
      throw FormatException('trusted identity: bad $field');
    }

    DateTime? instant(String field, {bool required = false}) {
      final value = json[field];
      if (value == null && !required) return null;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      throw FormatException('trusted identity: bad $field');
    }

    return TrustedIdentity(
      userId: text('userId'),
      deviceId: text('deviceId'),
      identityKey: text('identityKey'),
      firstSeenAt: instant('firstSeenAtMs', required: true)!,
      verifiedAt: instant('verifiedAtMs'),
      approvedAt: instant('approvedAtMs'),
    );
  }
}
