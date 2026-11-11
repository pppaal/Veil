import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veil_mobile/src/core/network/pinned_http_client.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/pinned_socket_http_client_adapter.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';

// Real TLS handshakes against a loopback server that sends a localhost leaf
// followed by the intermediate that issued it (tls_chain.pem), the way every
// public-CA server is configured. dart:io hands chain-verification callbacks
// the topmost certificate it was sent, so only a handshake with a real chain
// shows which certificate the pins are checked against. The CA keys were
// discarded; tls_leaf_key.pem is the leaf's throwaway key.
//
// Expected fingerprints were computed with OpenSSL 3.0 when the chain was
// generated, independently of the Dart code under test:
//   SPKI: openssl x509 -pubkey -noout | openssl pkey -pubin -outform der
//           | openssl dgst -sha256 -binary | base64
//   leaf: openssl x509 -outform der | openssl dgst -sha256 -binary | base64
const _leafSpki = 'ExRB6CSBirD+61VrlVK+3ilGixLLL2i8M7tjM2/w8bo=';
const _leafHash = 'Xw7Gm2ycxahC/wLSkzPuD+xT9pox8RKDmvFwqq/HnMg=';
const _intermediateSpki = '7u5O+++M/WNEyj3n2FvzzDGc+Uz0NkX2PxbrZ4eTPhQ=';
const _intermediateHash = 'ER4eqS3pVpOQPi2McwWWRjJecf1XIDhrpIwKYbkvCkY=';

const _intermediatePins = {
  'spki:$_intermediateSpki',
  'leaf:$_intermediateHash',
};

/// Answers plain requests with 'ok' and WebSocket upgrades with one 'hello'
/// frame, recording every request that reached the HTTP layer.
class _LoopbackServer {
  _LoopbackServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_LoopbackServer> tls() async {
    final context = SecurityContext()
      ..useCertificateChain('test/transport/fixtures/tls_chain.pem')
      ..usePrivateKey('test/transport/fixtures/tls_leaf_key.pem');
    return _LoopbackServer._(
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context),
    );
  }

  static Future<_LoopbackServer> plaintext() async {
    return _LoopbackServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
  }

  final HttpServer _server;
  final List<Uri> requests = [];
  final Completer<Uri> _firstRequest = Completer<Uri>();

  Future<Uri> get firstRequest => _firstRequest.future;

  Uri url(String scheme, [String path = '/']) =>
      Uri(scheme: scheme, host: '127.0.0.1', port: _server.port, path: path);

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    if (!_firstRequest.isCompleted) {
      _firstRequest.complete(request.uri);
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add('hello');
      await socket.close();
      return;
    }
    request.response.write('ok');
    await request.response.close();
  }
}

Matcher _pinMismatchShowingLeaf() {
  return isA<PinnedCertificateException>()
      .having((e) => e.host, 'host', '127.0.0.1')
      .having((e) => e.fingerprint, 'fingerprint', _leafHash);
}

void main() {
  late _LoopbackServer server;

  setUp(() async {
    server = await _LoopbackServer.tls();
  });

  tearDown(() => server.close());

  group('buildPinnedHttpClient against a leaf+intermediate chain', () {
    Future<http.Response> getWith(Set<String> pins) {
      final client = buildPinnedHttpClient(allowedFingerprints: pins);
      addTearDown(client.close);
      return client.get(server.url('https'));
    }

    test('a leaf SPKI pin connects', () async {
      final response = await getWith({'spki:$_leafSpki'});

      expect(response.statusCode, 200);
      expect(response.body, 'ok');
      expect(server.requests, hasLength(1));
    });

    test('a leaf hash pin connects, prefixed or legacy', () async {
      expect((await getWith({'leaf:$_leafHash'})).body, 'ok');
      expect((await getWith({_leafHash})).body, 'ok');
    });

    test('intermediate pins are rejected before a request byte is sent',
        () async {
      await expectLater(
        getWith(_intermediatePins),
        throwsA(_pinMismatchShowingLeaf()),
      );
      expect(server.requests, isEmpty);
    });

    test('a pin mismatch reaches API callers as tls_pin_mismatch', () async {
      final client = buildPinnedHttpClient(allowedFingerprints: _intermediatePins);
      addTearDown(client.close);
      final api = VeilApiClient(
        baseUrl: server.url('https', '/v1').toString(),
        client: client,
      );

      await expectLater(
        api.getKeyBundle('alice'),
        throwsA(
          isA<VeilApiException>()
              .having((e) => e.code, 'code', 'tls_pin_mismatch'),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('plaintext is refused once pins are configured', () async {
      final plaintext = await _LoopbackServer.plaintext();
      addTearDown(plaintext.close);
      final client = buildPinnedHttpClient(allowedFingerprints: {'spki:$_leafSpki'});
      addTearDown(client.close);

      await expectLater(
        client.get(plaintext.url('http')),
        throwsA(
          isA<PinnedCertificateException>()
              .having((e) => e.fingerprint, 'fingerprint', isNull),
        ),
      );
      expect(plaintext.requests, isEmpty);
    });

    test('a handshake that never completes is bounded by the connection timeout',
        () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await silent.close();
      });
      final client = buildPinnedHttpClient(
        allowedFingerprints: {'spki:$_leafSpki'},
        connectionTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://127.0.0.1:${silent.port}/')),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('buildPinnedDartIoHttpClient for the realtime WebSocket', () {
    Future<WebSocket> openWith(Set<String> pins) {
      final client = buildPinnedDartIoHttpClient(pins)!;
      addTearDown(() => client.close(force: true));
      return PinnedSocketHttpClientAdapter(client)
          .connect(server.url('wss', '/v1/realtime').toString());
    }

    test('a leaf SPKI pin opens the socket', () async {
      final socket = await openWith({'spki:$_leafSpki'});

      expect(await socket.first, 'hello');
    });

    test('a leaf hash pin opens the socket', () async {
      final socket = await openWith({'leaf:$_leafHash'});

      expect(await socket.first, 'hello');
    });

    test('intermediate pins fail the upgrade before it is sent', () async {
      await expectLater(
        openWith(_intermediatePins),
        throwsA(_pinMismatchShowingLeaf()),
      );
      expect(server.requests, isEmpty);
    });
  });

  // Drives the real socket.io client, so this also covers the option
  // plumbing RealtimeService -> io.io -> Manager -> WebSocket transport.
  group('RealtimeService over the pinned socket', () {
    RealtimeService connectWith(
      Set<String> pins, {
      void Function(bool connected)? onConnectionChanged,
    }) {
      final service = RealtimeService(
        httpClientFactory: () => buildPinnedDartIoHttpClient(pins),
      );
      addTearDown(service.disconnect);
      service.connect(
        baseUrl: server.url('https').toString(),
        accessToken: 'token-1',
        onEvent: (_, __) {},
        onConnectionChanged: onConnectionChanged,
      );
      return service;
    }

    test('the upgrade reaches the relay through the pinned client', () async {
      connectWith({'spki:$_leafSpki'});

      final upgrade = await server.firstRequest.timeout(const Duration(seconds: 10));
      expect(upgrade.path, '/v1/realtime/');
      expect(upgrade.queryParameters['transport'], 'websocket');
    });

    test('a pin mismatch keeps the upgrade off the wire', () async {
      final failedAttempt = Completer<void>();
      connectWith(
        _intermediatePins,
        onConnectionChanged: (connected) {
          if (!connected && !failedAttempt.isCompleted) {
            failedAttempt.complete();
          }
        },
      );

      await failedAttempt.future.timeout(const Duration(seconds: 10));
      expect(server.requests, isEmpty);
    });
  });
}
