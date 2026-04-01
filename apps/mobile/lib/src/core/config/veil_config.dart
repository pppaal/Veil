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
}
