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

  static bool get hasApi => apiBaseUrl.isNotEmpty;

  static String? get runtimeConfigurationError {
    final apiError = _validateEndpoint(
      apiBaseUrl,
      label: 'API',
      allowHttpPaths: true,
    );
    if (apiError != null) {
      return apiError;
    }

    return _validateEndpoint(
      realtimeUrl,
      label: 'Realtime',
      allowHttpPaths: false,
    );
  }

  static String? _validateEndpoint(
    String raw, {
    required String label,
    required bool allowHttpPaths,
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
