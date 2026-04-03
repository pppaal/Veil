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

abstract class PlatformSecurityService {
  Future<void> applyPrivacyProtections();

  Future<PlatformSecurityStatus> getStatus();

  Future<void> excludePathFromBackup(String path);
}

class MethodChannelPlatformSecurityService implements PlatformSecurityService {
  const MethodChannelPlatformSecurityService();

  static const _channel = MethodChannel('veil/platform_security');

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

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
}
