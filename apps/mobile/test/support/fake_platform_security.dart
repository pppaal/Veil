import 'dart:async';

import 'package:veil_mobile/src/core/security/platform_security_service.dart';

/// The platform security channel as a test sees it: it records the lock
/// calls in order, emits events on request, and reports the integrity a test
/// sets.
class RecordingPlatformSecurity implements PlatformSecurityService {
  final StreamController<PlatformSecurityEvent> _events = StreamController<PlatformSecurityEvent>.broadcast();

  /// Every lock call, in the order made: lockEngaged, lockScreenShown,
  /// sessionUnlocked.
  final List<String> calls = [];

  /// Paths asked to be excluded from backup.
  final List<String> excludedFromBackup = [];

  /// What getStatus reports as compromised integrity.
  bool integrityCompromised = false;

  int count(String call) => calls.where((made) => made == call).length;

  /// Sends [event] as the platform would.
  void emit(PlatformSecurityEvent event) => _events.add(event);

  @override
  Stream<PlatformSecurityEvent> get events => _events.stream;

  @override
  Future<void> applyPrivacyProtections() async {}

  @override
  Future<PlatformSecurityStatus> getStatus() async => PlatformSecurityStatus(
        appPreviewProtectionEnabled: true,
        screenCaptureProtectionSupported: true,
        screenCaptureProtectionEnabled: true,
        integrityCompromised: integrityCompromised,
        integrityReasons: integrityCompromised ? const ['test'] : const [],
      );

  @override
  Future<void> excludePathFromBackup(String path) async => excludedFromBackup.add(path);

  @override
  Future<void> lockEngaged() async => calls.add('lockEngaged');

  @override
  Future<void> lockScreenShown() async => calls.add('lockScreenShown');

  @override
  Future<void> sessionUnlocked() async => calls.add('sessionUnlocked');

  Future<void> close() => _events.close();
}
