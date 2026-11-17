import 'dart:io';

import 'package:flutter/services.dart';

class PlatformSecurityStatus {
  const PlatformSecurityStatus({
    required this.appPreviewProtectionEnabled,
    required this.screenCaptureProtectionSupported,
    required this.screenCaptureProtectionEnabled,
    required this.integrityCompromised,
    this.integrityReasons = const <String>[],
  });

  final bool appPreviewProtectionEnabled;
  final bool screenCaptureProtectionSupported;
  final bool screenCaptureProtectionEnabled;
  final bool integrityCompromised;
  final List<String> integrityReasons;

  factory PlatformSecurityStatus.fromMap(Map<Object?, Object?> raw) {
    final reasons =
        (raw['integrityReasons'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    return PlatformSecurityStatus(
      appPreviewProtectionEnabled:
          raw['appPreviewProtectionEnabled'] as bool? ?? false,
      screenCaptureProtectionSupported:
          raw['screenCaptureProtectionSupported'] as bool? ?? false,
      screenCaptureProtectionEnabled:
          raw['screenCaptureProtectionEnabled'] as bool? ?? false,
      integrityCompromised: raw['integrityCompromised'] as bool? ?? false,
      integrityReasons: reasons,
    );
  }

  static const unsupported = PlatformSecurityStatus(
    appPreviewProtectionEnabled: false,
    screenCaptureProtectionSupported: false,
    screenCaptureProtectionEnabled: false,
    integrityCompromised: false,
  );
}

enum PlatformSecurityEvent {
  screenshotDetected,

  /// iOS: the scene entered the background (Home, the app switcher, another
  /// app), which a system sheet presented over Veil never causes. The app
  /// locks on it whatever is up (SystemSheetGrace).
  sceneEnteredBackground,
}

abstract class PlatformSecurityService {
  Future<void> applyPrivacyProtections();

  Future<PlatformSecurityStatus> getStatus();

  Future<void> excludePathFromBackup(String path);

  Stream<PlatformSecurityEvent> get events;

  /// The session just locked. iOS closes whatever is presented over the app
  /// (Quick Look, a picker, the save sheet) and keeps its privacy cover
  /// until [lockScreenShown]; Android has nothing to do.
  Future<void> lockEngaged();

  /// The lock screen has been drawn, so the cover may go.
  Future<void> lockScreenShown();

  /// The session is no longer locked (unlocked, or signed out).
  Future<void> sessionUnlocked();
}

class MethodChannelPlatformSecurityService implements PlatformSecurityService {
  MethodChannelPlatformSecurityService();

  static const _channel = MethodChannel('veil/platform_security');
  static const _eventChannel = EventChannel('veil/platform_security_events');

  Stream<PlatformSecurityEvent>? _eventStream;

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Stream<PlatformSecurityEvent> get events {
    if (!_isSupportedPlatform) {
      return const Stream<PlatformSecurityEvent>.empty();
    }
    return _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) {
          if (raw is! Map) return null;
          return switch (raw['type']) {
            'screenshotDetected' => PlatformSecurityEvent.screenshotDetected,
            'sceneEnteredBackground' => PlatformSecurityEvent.sceneEnteredBackground,
            _ => null,
          };
        })
        .where((event) => event != null)
        .cast<PlatformSecurityEvent>();
  }

  @override
  Future<void> applyPrivacyProtections() async {
    if (!_isSupportedPlatform) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('applyPrivacyProtections');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<PlatformSecurityStatus> getStatus() async {
    if (!_isSupportedPlatform) {
      return PlatformSecurityStatus.unsupported;
    }

    try {
      final result =
          await _channel.invokeMapMethod<Object?, Object?>('getSecurityStatus');
      if (result == null) {
        return PlatformSecurityStatus.unsupported;
      }
      return PlatformSecurityStatus.fromMap(result);
    } on MissingPluginException {
      return PlatformSecurityStatus.unsupported;
    } on PlatformException {
      return PlatformSecurityStatus.unsupported;
    }
  }

  @override
  Future<void> excludePathFromBackup(String path) async {
    if (!_isSupportedPlatform || path.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('excludePathFromBackup', {
        'path': path,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<void> lockEngaged() => _notify('lockEngaged');

  @override
  Future<void> lockScreenShown() => _notify('lockScreenShown');

  @override
  Future<void> sessionUnlocked() => _notify('sessionUnlocked');

  Future<void> _notify(String method) async {
    if (!_isSupportedPlatform) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
