import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// How far the account trusts one of its devices, as the relay lists it.
enum DeviceTrustState { current, preferred, trusted, stale, revoked }

DeviceTrustState _parseTrustState(String? raw) => switch (raw) {
      'current' => DeviceTrustState.current,
      'preferred' => DeviceTrustState.preferred,
      'stale' => DeviceTrustState.stale,
      'revoked' => DeviceTrustState.revoked,
      _ => DeviceTrustState.trusted,
    };

/// One device of the account.
class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.trustState,
    required this.createdAt,
    required this.lastSeenAt,
    required this.lastTrustedActivityAt,
    this.revokedAt,
    this.trustedAt,
    this.joinedFromDeviceId,
    this.joinedFromDeviceName,
    this.lastSyncAt,
  });

  final String id;
  final String deviceName;
  final String platform;
  final DeviceTrustState trustState;
  final DateTime createdAt;

  /// The relay keeps only the UTC day of these three.
  final DateTime lastSeenAt;
  final DateTime? lastSyncAt;
  final DateTime lastTrustedActivityAt;

  final DateTime? revokedAt;
  final DateTime? trustedAt;
  final String? joinedFromDeviceId;
  final String? joinedFromDeviceName;

  /// Whether the device can still be revoked from this one: not this
  /// device (which has its own action), and not one already revoked.
  bool get canBeRevoked => trustState != DeviceTrustState.current && trustState != DeviceTrustState.revoked;

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) => json[key] == null ? null : DateTime.parse(json[key] as String);
    final lastSeenAt = DateTime.parse(json['lastSeenAt'] as String);
    final lastSyncAt = at('lastSyncAt');
    return TrustedDevice(
      id: json['id'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      trustState: _parseTrustState(json['trustState'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSeenAt: lastSeenAt,
      revokedAt: at('revokedAt'),
      trustedAt: at('trustedAt'),
      joinedFromDeviceId: json['joinedFromDeviceId'] as String?,
      joinedFromDeviceName: json['joinedFromDeviceName'] as String?,
      lastSyncAt: lastSyncAt,
      lastTrustedActivityAt: at('lastTrustedActivityAt') ?? lastSyncAt ?? lastSeenAt,
    );
  }
}

const _trustOrder = <DeviceTrustState, int>{
  DeviceTrustState.current: 0,
  DeviceTrustState.preferred: 1,
  DeviceTrustState.trusted: 2,
  DeviceTrustState.stale: 3,
  DeviceTrustState.revoked: 4,
};

/// The account's devices: this one first, revoked ones last, and within a
/// state the most recently active first.
class TrustedDeviceList {
  const TrustedDeviceList(this.devices);

  const TrustedDeviceList.empty() : devices = const [];

  factory TrustedDeviceList.fromJson(Map<String, dynamic> response) {
    final devices = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(TrustedDevice.fromJson)
        .toList(growable: false)
      ..sort((left, right) {
        final byTrust = _trustOrder[left.trustState]! - _trustOrder[right.trustState]!;
        return byTrust != 0 ? byTrust : right.lastTrustedActivityAt.compareTo(left.lastTrustedActivityAt);
      });
    return TrustedDeviceList(devices);
  }

  final List<TrustedDevice> devices;

  int _count(DeviceTrustState state) => devices.where((device) => device.trustState == state).length;

  /// Devices that can open the account today: every one not revoked.
  int get activeCount => devices.length - revokedCount;

  /// Other devices that are trusted and recently active.
  int get trustedCount => _count(DeviceTrustState.trusted);

  /// Trusted devices with no recent activity: each is worth a look.
  int get staleCount => _count(DeviceTrustState.stale);
  int get revokedCount => _count(DeviceTrustState.revoked);

  TrustedDevice? get preferred => devices.where((device) => device.trustState == DeviceTrustState.preferred).firstOrNull;

  TrustedDevice? byId(String? id) => devices.where((device) => device.id == id).firstOrNull;

  /// The latest activity of a device that is still trusted.
  DateTime? get mostRecentTrustedActivity => devices
      .where((device) => device.trustState != DeviceTrustState.revoked)
      .map((device) => device.lastTrustedActivityAt)
      .fold<DateTime?>(null, (latest, at) => latest == null || at.isAfter(latest) ? at : latest);
}

/// The devices the relay lists for the signed-in account. Read again
/// after `ref.invalidate` (a refresh, a revocation).
final trustedDevicesProvider = FutureProvider.autoDispose<TrustedDeviceList>((ref) async {
  // Whether there is a session, not its token: a token refresh must not
  // reload the list under the user's hands.
  final signedIn = ref.watch(appSessionProvider.select((session) => session.accessToken != null));
  if (!signedIn) return const TrustedDeviceList.empty();
  final accessToken = ref.read(appSessionProvider).accessToken!;
  return TrustedDeviceList.fromJson(await ref.read(apiClientProvider).listDevices(accessToken));
});
