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

  static const mockAuthSharedSecret = String.fromEnvironment(
    'VEIL_MOCK_AUTH_SHARED_SECRET',
    defaultValue: 'dev-device-auth-secret',
  );

  static bool get hasApi => apiBaseUrl.isNotEmpty;
}
