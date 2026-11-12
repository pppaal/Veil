import 'package:flutter/foundation.dart' show kReleaseMode;

import '../network/pinned_http_client.dart' show parsePinList;

class VeilConfig {
  const VeilConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'VEIL_API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  static const realtimeUrl = String.fromEnvironment(
    'VEIL_REALTIME_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const enableLocalCache = bool.fromEnvironment(
    'VEIL_ENABLE_LOCAL_CACHE',
    defaultValue: true,
  );

  // Comma-separated TLS pins ('spki:<b64>', 'leaf:<b64>' or legacy unprefixed
  // leaf pins; see pinned_http_client.dart) the client trusts for both the
  // API and the realtime WebSocket. Empty means "no pin" (dev mode).
  // Production builds MUST pass --dart-define VEIL_TLS_PINS=... so a
  // compromised CA can't transparently MITM the API connection or steal the
  // bearer token from the WebSocket handshake.
  static const tlsPins = String.fromEnvironment(
    'VEIL_TLS_PINS',
    defaultValue: '',
  );

  // Pins for the object store that receives encrypted attachment uploads
  // (presigned URLs usually point at a different host than the API). Same
  // format as [tlsPins]; empty falls back to the platform trust store.
  static const objectStoragePins = String.fromEnvironment(
    'VEIL_OBJECT_STORAGE_PINS',
    defaultValue: '',
  );

  // Comma-separated hostnames presigned upload URLs may point at. When set,
  // an upload ticket naming any other host is refused before a byte leaves
  // the device.
  static const objectStorageHosts = String.fromEnvironment(
    'VEIL_OBJECT_STORAGE_HOSTS',
    defaultValue: '',
  );

  static bool get hasApi => apiBaseUrl.isNotEmpty;

  /// Why this build cannot run, or null. Bootstrap, the route guard and the
  /// security status screen all stop on it.
  static String? get runtimeConfigurationError => validateRuntimeConfiguration(
        apiBaseUrl: apiBaseUrl,
        realtimeUrl: realtimeUrl,
        tlsPins: tlsPins,
        release: kReleaseMode,
      );

  /// The checks behind [runtimeConfigurationError]. A [release] build must
  /// name a relay that is not a local development host (which also forces
  /// https and wss, see below) and must pin its TLS keys: the defaults are
  /// for development only, and a store build left with them would talk to
  /// the device's own loopback address without any pin.
  static String? validateRuntimeConfiguration({
    required String apiBaseUrl,
    required String realtimeUrl,
    required String tlsPins,
    required bool release,
  }) {
    final apiError = _validateEndpoint(
      apiBaseUrl,
      label: 'API',
      allowHttpPaths: true,
      release: release,
    );
    if (apiError != null) {
      return apiError;
    }

    final realtimeError = _validateEndpoint(
      realtimeUrl,
      label: 'Realtime',
      allowHttpPaths: false,
      release: release,
    );
    if (realtimeError != null) {
      return realtimeError;
    }

    if (release && parsePinList(tlsPins).isEmpty) {
      return 'Release builds must pass VEIL_TLS_PINS.';
    }
    return null;
  }

  static String? _validateEndpoint(
    String raw, {
    required String label,
    required bool allowHttpPaths,
    required bool release,
  }) {
    if (raw.isEmpty) {
      return '$label endpoint is missing.';
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '$label endpoint is invalid.';
    }

    final isLocalHost = switch (uri.host) {
      'localhost' || '127.0.0.1' || '10.0.2.2' => true,
      _ => false,
    };

    if (release && isLocalHost) {
      return '$label endpoint points at a local development host; release builds must pass '
          'VEIL_API_BASE_URL and VEIL_REALTIME_URL.';
    }

    final allowedSchemes = allowHttpPaths ? {'http', 'https'} : {'ws', 'wss', 'http', 'https'};
    if (!allowedSchemes.contains(uri.scheme)) {
      return '$label endpoint must use a supported transport scheme.';
    }

    final isSecureScheme = switch (uri.scheme) {
      'https' || 'wss' => true,
      _ => false,
    };

    if (!isSecureScheme && !isLocalHost) {
      return '$label endpoint must use TLS outside local development.';
    }

    return null;
  }
}
