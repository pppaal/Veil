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
        api.getJson('/profile', accessToken: 'token').then((_) {}, onError: (Object e) {
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
        api.getJson('/profile', accessToken: 'token'),
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
        api.getJson('/profile', accessToken: 'token'),
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
        api.getJson('/profile', accessToken: 'token'),
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
        api.getJson('/profile', accessToken: 'stale'),
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
          api.getJson('/profile', accessToken: 'stale').then<Object>((value) => value, onError: (Object e) => e),
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
        api.getJson('/profile', accessToken: 'stale'),
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

      await api.getJson('/profile', accessToken: 'stale');
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

  group('attachment downloads', () {
    const attachmentId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
    const blobUrl = 'https://blobs.veil.test/attachments/x?signature=abc';
    final blob = List<int>.generate(4096, (i) => i % 251);

    VeilApiClient clientWithStorage(http.Client storage, {Duration uploadTimeout = kDefaultUploadTimeout}) {
      return VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) async => fail('downloads must not use the API client')),
        objectStorageClient: storage,
        objectStoragePolicy: _storagePolicy,
        uploadTimeout: uploadTimeout,
      );
    }

    // A body that counts what was taken from it, with or without a length.
    ({http.Client client, List<int> pulled}) streaming(List<int> bytes, {int? contentLength, int status = 200}) {
      final pulled = <int>[];
      Stream<List<int>> body() async* {
        for (var offset = 0; offset < bytes.length; offset += 1024) {
          final chunk = bytes.sublist(offset, offset + 1024 > bytes.length ? bytes.length : offset + 1024);
          pulled.add(chunk.length);
          yield chunk;
        }
      }

      return (
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(body(), status, contentLength: contentLength),
        ),
        pulled: pulled,
      );
    }

    test('a ticket for an id that is not a UUID makes no request', () async {
      var requests = 0;
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      for (final bad in ['../keys/x', 'abc', '$attachmentId/../../users', '', '$attachmentId?x=1']) {
        await expectLater(api.getDownloadTicket('token', bad), throwsA(_apiError('attachment_id_invalid')), reason: bad);
      }
      expect(requests, 0);
    });

    test('a ticket names the id in its own path segment', () async {
      final paths = <List<String>>[];
      final api = VeilApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          paths.add(request.url.pathSegments);
          return http.Response('{"ticket":{}}', 200);
        }),
      );
      await api.getDownloadTicket('token', attachmentId);
      await api.getDownloadTicket('token', attachmentId.toUpperCase());
      expect(paths, [
        ['v1', 'attachments', attachmentId, 'download-ticket'],
        ['v1', 'attachments', attachmentId.toUpperCase(), 'download-ticket'],
      ]);
    });

    test('a download goes through the storage client, without the bearer token', () async {
      final received = <http.BaseRequest>[];
      final progress = <(int, int?)>[];
      final api = clientWithStorage(MockClient((request) async {
        received.add(request);
        return http.Response.bytes(blob, 200);
      }));
      final bytes = await api.downloadEncryptedBlob(
        downloadUrl: blobUrl,
        maxBytes: blob.length,
        onProgress: (got, total) => progress.add((got, total)),
      );
      expect(bytes, blob);
      final request = received.single;
      expect(request.method, 'GET');
      expect(request.url.host, 'blobs.veil.test');
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
      expect(request.followRedirects, isFalse);
      expect(progress.last, (blob.length, blob.length));
    });

    test('a host outside the allowlist is refused before any request', () async {
      var storageCalls = 0;
      final api = clientWithStorage(MockClient((_) async {
        storageCalls += 1;
        return http.Response.bytes(blob, 200);
      }));
      await expectLater(
        api.downloadEncryptedBlob(downloadUrl: 'https://attacker.example/blob', maxBytes: 1 << 20),
        throwsA(_apiError('attachment_download_invalid')),
      );
      expect(storageCalls, 0);
    });

    test('release policy refuses plain http download URLs', () {
      expect(
        () => _storagePolicy.checkDownloadUrl('http://blobs.veil.test/object'),
        throwsA(_apiError('attachment_download_invalid')),
      );
      expect(() => _storagePolicy.checkDownloadUrl('not a url'), throwsA(_apiError('attachment_download_invalid')));
      expect(_storagePolicy.checkDownloadUrl(blobUrl).host, 'blobs.veil.test');
    });

    test('a redirect to another host is refused', () async {
      final api = clientWithStorage(MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://attacker.example/blob'},
        ),
      ));
      await expectLater(
        api.downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: 1 << 20),
        throwsA(_apiError('attachment_download_invalid')),
      );
    });

    test('statuses map to gone, refused and failed', () async {
      for (final (status, code) in [
        (404, 'attachment_not_found'),
        (403, 'attachment_forbidden'),
        (500, 'attachment_download_failed'),
        (503, 'attachment_download_failed'),
      ]) {
        final api = clientWithStorage(MockClient((_) async => http.Response('no', status)));
        await expectLater(
          api.downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: 1 << 20),
          throwsA(_apiError(code, statusCode: status)),
          reason: '$status',
        );
      }
    });

    test('a Content-Length over the cap stops before the body is read', () async {
      final body = streaming(blob, contentLength: blob.length);
      final progress = <int>[];
      await expectLater(
        clientWithStorage(body.client).downloadEncryptedBlob(
          downloadUrl: blobUrl,
          maxBytes: blob.length - 1,
          onProgress: (got, _) => progress.add(got),
        ),
        throwsA(_apiError('attachment_download_invalid')),
      );
      expect(progress, isEmpty);
      expect(body.pulled, isEmpty);
    });

    test('a body without a length stops once it runs past the cap', () async {
      final body = streaming(blob);
      final progress = <int>[];
      await expectLater(
        clientWithStorage(body.client).downloadEncryptedBlob(
          downloadUrl: blobUrl,
          maxBytes: 2500,
          onProgress: (got, _) => progress.add(got),
        ),
        throwsA(_apiError('attachment_download_invalid')),
      );
      expect(progress, [1024, 2048]);
      expect(body.pulled.length, lessThan(4));
      // Exactly at the cap is fine.
      final whole = streaming(blob);
      expect(await clientWithStorage(whole.client).downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: blob.length), blob);
    });

    test('a download that stalls throws network_timeout', () async {
      final api = clientWithStorage(
        MockClient((_) => Completer<http.Response>().future),
        uploadTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        api.downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: 1 << 20),
        throwsA(_apiError(TransportErrorCode.timeout)),
      );
    });

    test('a canceled download throws attachment_download_canceled', () async {
      final api = clientWithStorage(MockClient((_) => Completer<http.Response>().future));
      final signal = AttachmentUploadCancellationSignal();
      final download = api.downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: 1 << 20, cancellationSignal: signal);
      await pumpEventQueue();
      signal.cancel();
      await expectLater(download, throwsA(_apiError('attachment_download_canceled')));
    });

    test('a socket failure maps to network_unavailable', () async {
      final api = clientWithStorage(MockClient((_) => throw const SocketException('refused')));
      await expectLater(
        api.downloadEncryptedBlob(downloadUrl: blobUrl, maxBytes: 1 << 20),
        throwsA(_apiError(TransportErrorCode.unavailable)),
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

  test('an abuse report carries the FileAbuseReportRequest fields and no text', () async {
    final received = <http.Request>[];
    final api = VeilApiClient(
      baseUrl: _baseUrl,
      client: MockClient((request) async {
        received.add(request);
        return http.Response('{"id": "r-1"}', 201);
      }),
    );

    await api.fileAbuseReport(
      't',
      reportedUserId: '7d0f8f4e-8f3a-4c1e-9a55-0d6f2c1b9a01',
      reason: 'spam',
      conversationId: '0b8f6a2e-4c3d-4b5a-8e7f-1a2b3c4d5e6f',
      messageId: '9c1d2e3f-4a5b-4c6d-8e7f-a1b2c3d4e5f6',
    );

    expect(received.single.url.toString(), '$_baseUrl/safety/reports');
    expect((jsonDecode(received.single.body) as Map).keys.toSet(), {
      'reportedUserId',
      'reason',
      'conversationId',
      'messageId',
    });
  });

  // The API reads a missing mutedForSeconds as "no end" and null as "on
  // again": a mute with no end that sent null turned notifications back on.
  test('a mute sends its length, leaves it out for no end, and an unmute sends null', () async {
    const conversationId = '0b8f6a2e-4c3d-4b5a-8e7f-1a2b3c4d5e6f';
    final bodies = <Map<String, dynamic>>[];
    final api = VeilApiClient(
      baseUrl: _baseUrl,
      client: MockClient((request) async {
        expect(request.url.toString(), '$_baseUrl/safety/mutes/$conversationId');
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"mute": null}', 201);
      }),
    );

    await api.setConversationMute('t', conversationId, mutedForSeconds: 3600, unmute: false);
    await api.setConversationMute('t', conversationId, unmute: false);
    await api.setConversationMute('t', conversationId, unmute: true);

    expect(bodies[0], {'mutedForSeconds': 3600});
    expect(bodies[1], isEmpty);
    expect(bodies[2], {'mutedForSeconds': null});
  });
}
