import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

// The relay checks a signed prekey's timestamp against its own clock, so
// the device keeps the offset every API response reports in its Date header.
void main() {
  final local = DateTime.utc(2026, 11, 12, 9);

  ServerClock clockAt(DateTime Function() localNow) => ServerClock(localClock: localNow);

  test('is the local clock until a response says otherwise', () {
    final clock = clockAt(() => local);

    expect(clock.offset, Duration.zero);
    expect(clock.now(), local);
  });

  test('takes the offset from a Date header and ignores what does not parse', () {
    final clock = clockAt(() => local)..observe(HttpDate.format(local.add(const Duration(minutes: 47))));
    expect(clock.now(), local.add(const Duration(minutes: 47)));

    clock
      ..observe(null)
      ..observe('yesterday, around noon');
    expect(clock.offset, const Duration(minutes: 47));
  });

  test('the API client learns it from every response, refusals included', () async {
    var serverTime = local.subtract(const Duration(hours: 3));
    final api = VeilApiClient(
      baseUrl: 'https://api.veil.test/v1',
      serverClock: clockAt(() => local),
      client: MockClient((request) async {
        final date = {'date': HttpDate.format(serverTime)};
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({'code': 'signed_prekey_timestamp_out_of_window', 'message': 'stale'}),
            400,
            headers: date,
          );
        }
        return http.Response(jsonEncode({'available': 3}), 200, headers: date);
      }),
    );

    await api.getJson('/prekeys/count', accessToken: 'token');
    expect(api.serverClock.offset, const Duration(hours: -3));

    serverTime = local.add(const Duration(minutes: 20));
    await expectLater(
      api.putJson('/keys/signed-prekey', accessToken: 'token', body: const {'signedPrekeyBundle': 'b'}),
      throwsA(isA<VeilApiException>().having((e) => e.code, 'code', 'signed_prekey_timestamp_out_of_window')),
    );
    expect(api.serverClock.offset, const Duration(minutes: 20));
  });
}
