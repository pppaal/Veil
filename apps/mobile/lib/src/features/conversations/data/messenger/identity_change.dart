/// A contact identity this device will not use until the user accepts it:
/// a different key for a pinned device, or a new device of a contact whose
/// other device the user verified.
class PendingIdentityChange {
  const PendingIdentityChange({
    required this.conversationId,
    required this.userId,
    required this.deviceId,
    required this.presentedKey,
    required this.previousKey,
    required this.requiresReverification,
  });

  final String conversationId;
  final String userId;
  final String deviceId;

  /// The key the directory or the handshake presented, base64url.
  final String presentedKey;

  /// The pinned key it would replace; null for a new device.
  final String? previousKey;

  /// The user had verified this contact, so accepting the change takes a
  /// fresh out-of-band verification, never a single tap.
  final bool requiresReverification;

  /// Whether this change is about [identityKey] for the very same device.
  bool presents(String userId, String deviceId, String identityKey) =>
      this.userId == userId && this.deviceId == deviceId && presentedKey == identityKey;

  Map<String, dynamic> toJson() => {
        'conversationId': conversationId,
        'userId': userId,
        'deviceId': deviceId,
        'presentedKey': presentedKey,
        if (previousKey != null) 'previousKey': previousKey,
        'requiresReverification': requiresReverification,
      };

  /// Throws on a record of the wrong shape.
  factory PendingIdentityChange.fromJson(Map<String, dynamic> json) => PendingIdentityChange(
        conversationId: json['conversationId'] as String,
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        presentedKey: json['presentedKey'] as String,
        previousKey: json['previousKey'] as String?,
        requiresReverification: json['requiresReverification'] as bool,
      );
}

/// Thrown when an operation needs an identity the user has not accepted.
/// Scoped to one conversation: the chat shows it, not a global error.
class IdentityChangedException implements Exception {
  const IdentityChangedException(this.change);

  final PendingIdentityChange change;

  @override
  String toString() => 'The safety number for this conversation changed. Review it before sending.';
}

/// What the trust layer tells the messenger as it decides.
sealed class IdentityTrustEvent {
  const IdentityTrustEvent(this.conversationId);

  final String conversationId;
}

/// A change became pending; the conversation gets the 'identity.changed'
/// notice once.
final class IdentityChangePending extends IdentityTrustEvent {
  IdentityChangePending(this.change) : super(change.conversationId);

  final PendingIdentityChange change;
}

/// A new device of an unverified contact was admitted; the conversation
/// gets the 'identity.new_device' notice once.
final class NewDeviceAdmitted extends IdentityTrustEvent {
  const NewDeviceAdmitted(super.conversationId, {required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;
}

/// A pending change was accepted, declined, or no longer applies.
final class IdentityChangeResolved extends IdentityTrustEvent {
  const IdentityChangeResolved(super.conversationId);
}
