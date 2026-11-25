import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/config/veil_config.dart';

// A store build made with only --dart-define=VEIL_ENV=prod (which nothing in
// the app reads) used to start "compliant" against http://localhost:3000
// with no TLS pins. Release builds now refuse that configuration.
void main() {
  const pins = 'spki:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=,spki:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';

  String? check({
    String api = 'https://api.veil.example/v1',
    String realtime = 'https://api.veil.example',
    String tlsPins = pins,
    required bool release,
  }) =>
      VeilConfig.validateRuntimeConfiguration(apiBaseUrl: api, realtimeUrl: realtime, tlsPins: tlsPins, release: release);

  group('a release build', () {
    test('runs with production endpoints and pins', () {
      expect(check(release: true), isNull);
      expect(check(realtime: 'wss://api.veil.example', release: true), isNull);
    });

    test('refuses the local development defaults', () {
      expect(check(api: 'http://localhost:3000/v1', realtime: 'http://localhost:3000', release: true),
          contains('API endpoint points at a local development host'));
      expect(check(realtime: 'http://10.0.2.2:3000', release: true),
          contains('Realtime endpoint points at a local development host'));
      expect(check(api: 'https://127.0.0.1/v1', release: true), contains('local development host'));
    });

    test('refuses to run without TLS pins', () {
      expect(check(tlsPins: '', release: true), 'Release builds must pass VEIL_TLS_PINS.');
      expect(check(tlsPins: ' , ', release: true), 'Release builds must pass VEIL_TLS_PINS.');
    });

    test('still refuses a plain-text relay', () {
      expect(check(api: 'http://api.veil.example/v1', release: true), contains('must use TLS'));
    });
  });

  test('a development build keeps the local defaults and needs no pins', () {
    expect(check(api: 'http://localhost:3000/v1', realtime: 'http://localhost:3000', tlsPins: '', release: false), isNull);
    expect(check(api: 'http://api.veil.example/v1', release: false), contains('must use TLS'));
  });

  test('the configuration this test binary was built with is a development one', () {
    // flutter test never compiles in release mode, so the defaults pass.
    expect(VeilConfig.runtimeConfigurationError, isNull);
  });
}
