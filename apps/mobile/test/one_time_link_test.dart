import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/core/network/veil_api_exception.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link_service.dart';

void main() {
  const secret = '넷플릭스 비번 Vx9\$kQ2! / 계좌 3333-04 🔐';

  test('key mode round-trips and keeps the key out of the blob', () async {
    final sealed = await OneTimeLink.seal(secret);
    expect(sealed.blob, startsWith('v1.'));
    expect(sealed.fragment, startsWith('k.'));
    // server blob must not contain the key or plaintext
    expect(sealed.blob.contains(sealed.fragment.substring(2)), isFalse);
    expect(sealed.blob.contains('3333-04'), isFalse);

    final opened = await OneTimeLink.open(sealed.blob, sealed.fragment);
    expect(opened, secret);
  });

  test('passphrase mode keeps the key out of the link (salt only)', () async {
    final sealed = await OneTimeLink.seal(secret, passphrase: 'open-sesame');
    expect(sealed.fragment, 'p');
    expect(sealed.blob.split('.'), hasLength(4)); // v1.iv.ct.salt

    final opened =
        await OneTimeLink.open(sealed.blob, 'p', passphrase: 'open-sesame');
    expect(opened, secret);
  });

  test('wrong passphrase is rejected', () async {
    final sealed = await OneTimeLink.seal(secret, passphrase: 'right');
    await expectLater(
      OneTimeLink.open(sealed.blob, 'p', passphrase: 'wrong'),
      throwsA(anything),
    );
  });

  test('ciphertext carries the appended 16-byte GCM tag (WebCrypto layout)',
      () async {
    final sealed = await OneTimeLink.seal('hi'); // 2-byte plaintext
    final ctB64 = sealed.blob.split('.')[2];
    final ctLen =
        base64Url.decode(ctB64.padRight((ctB64.length + 3) & ~3, '=')).length;
    expect(ctLen, 2 + 16); // plaintext + tag
  });

  group('OneTimeLinkService', () {
    test('posts only the ciphertext and keeps the key in the fragment', () async {
      late http.Request posted;
      final service = OneTimeLinkService(
        apiBaseUrl: 'https://api.veil.test/v1',
        client: MockClient((request) async {
          posted = request;
          return http.Response(jsonEncode({'id': 'link-1'}), 201);
        }),
      );

      final link = await service.createLink(secret);

      expect(posted.url.toString(), 'https://api.veil.test/v1/s');
      final body = jsonDecode(posted.body) as Map<String, dynamic>;
      expect(body.keys, ['ciphertext']);
      final fragment = Uri.parse(link).fragment;
      expect(link, startsWith('https://api.veil.test/demo/s.html#link-1.k.'));
      expect(posted.body.contains(fragment.split('.k.').last), isFalse);
      expect(
        await OneTimeLink.open(body['ciphertext'] as String, fragment.substring('link-1.'.length)),
        secret,
      );
    });

    test('a stalled request times out instead of hanging the screen', () async {
      final service = OneTimeLinkService(
        apiBaseUrl: 'https://api.veil.test/v1',
        client: MockClient((_) => Completer<http.Response>().future),
        requestTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.createLink('x'),
        throwsA(
          isA<VeilApiException>()
              .having((e) => e.code, 'code', 'network_timeout'),
        ),
      );
    });

    test('an unreachable relay is reported as network_unavailable', () async {
      final service = OneTimeLinkService(
        apiBaseUrl: 'https://api.veil.test/v1',
        client: MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      await expectLater(
        service.createLink('x'),
        throwsA(
          isA<VeilApiException>()
              .having((e) => e.code, 'code', 'network_unavailable'),
        ),
      );
    });
  });
}
