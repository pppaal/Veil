import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/core/network/http_transport.dart';
import 'package:veil_mobile/src/core/network/pinned_http_client.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

const _baseUrl = 'https://api.veil.test/v1';
const _storagePolicy = ObjectStoragePolicy(
  allowedHosts: {'blobs.veil.test'},
  requireHttps: true,
);

Matcher _apiError(String code, {int? statusCode}) {
  var matcher = isA<VeilApiException>().having((e) => e.code, 'code', code);
  if (statusCode != null) {
    matcher = matcher.having((e) => e.statusCode, 'statusCode', statusCode);
  }
  return matcher;
}

void main() {
  group('request timeouts and transport errors', () {
    test('never-completing response throws network_timeout', () {
      fakeAsync((async) {
        final api = VeilApiClient(
          baseUrl: _baseUrl,
          client: MockClient((_) => Completer<http.Response>().future),
        );
        Object? error;
        api.getProfile('token').then((_) {}, onError: (Object e) {
          error = e;
        });

        async.elapse(kDefaultRequestTimeout - const Duration(seconds: 1));
        expect(error, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(error, _apiError(TransportErrorCode.timeout));
      });
    });

    test('socket failure maps to network_unavailable', () async {
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) => throw const SocketException('refused')),
      );

      await expectLater(
        api.getProfile('token'),
        throwsA(_apiError(TransportErrorCode.unavailable)),
      );
    });

    test('pin rejection maps to tls_pin_mismatch', () async {
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) => throw const PinnedCertificateException('api.veil.test', 'x'),
        ),
      );

      await expectLater(
        api.getProfile('token'),
        throwsA(_apiError(TransportErrorCode.pinMismatch)),
      );
    });

    test('HTTP errors keep their status and server code', () async {
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'device_not_active', 'message': 'gone'}),
            403,
          ),
        ),
      );

      await expectLater(
        api.getProfile('token'),
        throwsA(_apiError('device_not_active', statusCode: 403)),
      );
    });
  });

  group('single-flight token refresh', () {
    test('three concurrent 401s trigger one refresh and all replay', () async {
      final authorizations = <String?>[];
      final client = MockClient((request) async {
        final authorization = request.headers['Authorization'];
        authorizations.add(authorization);
        if (authorization == 'Bearer stale') {
          return http.Response('', 401);
        }
        return http.Response(jsonEncode({'path': request.url.path}), 200);
      });
      final refresh = Completer<String?>();
      var refreshCalls = 0;
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: client,
        tokenRefresher: () {
          refreshCalls += 1;
          return refresh.future;
        },
      );

      final responses = Future.wait([
        api.getProfile('stale'),
        api.listDevices('stale'),
        api.getConversations('stale'),
      ]);
      // Let all three initial requests come back 401 while the refresh is
      // still in flight.
      await pumpEventQueue();
      refresh.complete('fresh');

      expect(
        (await responses).map((body) => body['path']),
        ['/v1/profile', '/v1/devices', '/v1/conversations'],
      );
      expect(refreshCalls, 1);
      expect(authorizations.where((a) => a == 'Bearer stale'), hasLength(3));
      expect(authorizations.where((a) => a == 'Bearer fresh'), hasLength(3));
    });

    test('refresh failure propagates 401 to all waiters', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests += 1;
        return http.Response(jsonEncode({'message': 'expired'}), 401);
      });
      var refreshCalls = 0;
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: client,
        tokenRefresher: () async {
          refreshCalls += 1;
          await pumpEventQueue();
          return null;
        },
      );

      final outcomes = await Future.wait([
        for (var i = 0; i < 3; i++)
          api.getProfile('stale').then<Object>((value) => value, onError: (Object e) => e),
      ]);

      expect(
        outcomes,
        everyElement(
          isA<VeilApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(refreshCalls, 1);
      expect(requests, 3, reason: 'no request may be replayed without a token');
    });

    test('a refresher that throws counts as a failed refresh', () async {
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) async => http.Response('', 401)),
        tokenRefresher: () => throw StateError('refresh store unavailable'),
      );

      await expectLater(
        api.getProfile('stale'),
        throwsA(isA<VeilApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('a late 401 for an already rotated token replays without refreshing again', () async {
      final client = MockClient((request) async {
        return request.headers['Authorization'] == 'Bearer stale'
            ? http.Response('', 401)
            : http.Response('{}', 200);
      });
      var refreshCalls = 0;
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: client,
        tokenRefresher: () async {
          refreshCalls += 1;
          return 'fresh-$refreshCalls';
        },
      );

      await api.getProfile('stale');
      await api.listDevices('stale');

      expect(refreshCalls, 1);
    });
  });

  group('attachment uploads', () {
    late Directory tempDir;
    late File blob;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('veil-upload-test');
      blob = File('${tempDir.path}/blob.bin')
        ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    VeilApiClient clientWithStorage(
      http.Client storage, {
      Duration uploadTimeout = kDefaultUploadTimeout,
    }) {
      return VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) async => fail('uploads must not use the API client')),
        objectStorageClient: storage,
        objectStoragePolicy: _storagePolicy,
        uploadTimeout: uploadTimeout,
      );
    }

    test('upload uses injected object storage client', () async {
      final received = <http.Request>[];
      final api = clientWithStorage(MockClient((request) async {
        received.add(request);
        return http.Response('', 200);
      }));
      final progress = <int>[];

      await api.uploadEncryptedBlobFile(
        uploadUrl: 'https://blobs.veil.test/bucket/object?signature=abc',
        headers: const {'Content-Type': 'application/octet-stream'},
        file: blob,
        onProgress: (sent, total) => progress.add(sent),
      );

      final request = received.single;
      expect(request.method, 'PUT');
      expect(request.url.host, 'blobs.veil.test');
      expect(request.headers['Content-Type'], 'application/octet-stream');
      expect(request.bodyBytes, blob.readAsBytesSync());
      expect(progress.last, 4096);
    });

    test('upload to non-allowlisted host rejected', () async {
      var storageCalls = 0;
      final api = clientWithStorage(MockClient((_) async {
        storageCalls += 1;
        return http.Response('', 200);
      }));

      await expectLater(
        api.uploadEncryptedBlobFile(
          uploadUrl: 'https://attacker.example/bucket/object',
          headers: const {},
          file: blob,
        ),
        throwsA(_apiError('attachment_upload_invalid')),
      );
      expect(storageCalls, 0);
    });

    test('release policy rejects plain http upload URLs', () {
      expect(
        () => _storagePolicy.checkUploadUrl('http://blobs.veil.test/object'),
        throwsA(_apiError('attachment_upload_invalid')),
      );
      expect(
        const ObjectStoragePolicy(requireHttps: false)
            .checkUploadUrl('http://localhost:9000/object')
            .host,
        'localhost',
      );
    });

    test('stalled upload throws network_timeout', () async {
      final api = clientWithStorage(
        MockClient((_) => Completer<http.Response>().future),
        uploadTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        api.uploadEncryptedBlobFile(
          uploadUrl: 'https://blobs.veil.test/object',
          headers: const {},
          file: blob,
        ),
        throwsA(_apiError(TransportErrorCode.timeout)),
      );
    });

    test('canceled upload throws attachment_upload_canceled', () async {
      final api = clientWithStorage(
        MockClient((_) => Completer<http.Response>().future),
      );
      final signal = AttachmentUploadCancellationSignal();

      final upload = api.uploadEncryptedBlobFile(
        uploadUrl: 'https://blobs.veil.test/object',
        headers: const {},
        file: blob,
        cancellationSignal: signal,
      );
      await pumpEventQueue();
      signal.cancel();

      await expectLater(upload, throwsA(_apiError('attachment_upload_canceled')));
    });

    test('storage HTTP error is a retryable attachment_upload_failed', () async {
      final api = clientWithStorage(
        MockClient((_) async => http.Response('denied', 503)),
      );

      await expectLater(
        api.uploadEncryptedBlobFile(
          uploadUrl: 'https://blobs.veil.test/object',
          headers: const {},
          file: blob,
        ),
        throwsA(_apiError('attachment_upload_failed', statusCode: 503)),
      );
    });
  });

  group('authenticated JSON helpers', () {
    test('a missing token fails with unauthorized before any request', () async {
      var requests = 0;
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.getJson('/keys/atlas', accessToken: null),
        throwsA(_apiError('unauthorized')),
      );
      await expectLater(
        api.postJson('/keys/signed-prekey', accessToken: '', body: const {}),
        throwsA(_apiError('unauthorized')),
      );
      expect(requests, 0);
    });

    test('helpers send method, bearer token, query and JSON body', () async {
      final received = <http.Request>[];
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          received.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      );

      await api.getJson('/keys/atlas', accessToken: 't', query: {'device': 'd1'});
      await api.putJson('/keys/signed-prekey', accessToken: 't', body: {'spkId': 2});
      await api.deleteJson('/contacts/atlas', accessToken: 't');

      expect(received.map((r) => r.method), ['GET', 'PUT', 'DELETE']);
      expect(received.first.url.toString(), '$_baseUrl/keys/atlas?device=d1');
      expect(received.map((r) => r.headers['Authorization']), everyElement('Bearer t'));
      expect(jsonDecode(received[1].body), {'spkId': 2});
      expect(received.last.body, isEmpty);
    });

    test('an empty query leaves no bare "?" on the URL', () async {
      final received = <Uri>[];
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          received.add(request.url);
          return http.Response('{}', 200);
        }),
      );

      await api.getJson('/keys/atlas', accessToken: 't', query: const {});

      expect(received.single.toString(), '$_baseUrl/keys/atlas');
    });
  });
}
