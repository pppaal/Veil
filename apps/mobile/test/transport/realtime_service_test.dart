import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/network/pinned_http_client.dart';
import 'package:veil_mobile/src/core/realtime/pinned_socket_http_client_adapter.dart';
import 'package:veil_mobile/src/core/realtime/realtime_events.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/realtime/realtime_socket.dart';

class _FakeSocket implements RealtimeSocket {
  final Map<String, void Function(dynamic payload)> handlers = {};
  final List<Map<String, dynamic>> authHistory = [];
  void Function(bool connected)? connectionListener;
  int connectCount = 0;
  int disconnectCount = 0;
  bool disposed = false;

  @override
  bool connected = false;

  @override
  set auth(Map<String, dynamic> value) => authHistory.add(value);

  @override
  void on(String event, void Function(dynamic payload) handler) {
    handlers[event] = handler;
  }

  @override
  void onConnectionChanged(void Function(bool connected) listener) {
    connectionListener = listener;
  }

  @override
  void emit(String event, Map<String, dynamic> payload) {}

  @override
  void connect() {
    connectCount += 1;
    connected = true;
  }

  @override
  void disconnect() {
    disconnectCount += 1;
    connected = false;
  }

  @override
  void dispose() {
    disposed = true;
    connected = false;
  }

  void deliver(String event, Object? payload) => handlers[event]!(payload);
}

class _RecordingHttpClient extends Fake implements HttpClient {
  bool closed = false;

  @override
  void close({bool force = false}) => closed = true;
}

class _Harness {
  _Harness({PinnedHttpClientFactory? httpClientFactory}) {
    service = RealtimeService(
      httpClientFactory: httpClientFactory ?? () => null,
      socketFactory: (url, options) {
        socketUrls.add(url);
        socketOptions.add(options);
        return socket;
      },
    );
  }

  late final RealtimeService service;
  final socket = _FakeSocket();
  final socketUrls = <String>[];
  final socketOptions = <Map<String, dynamic>>[];
  final events = <(String, dynamic)>[];
  final connectionChanges = <bool>[];

  void connect({String token = 'token-1'}) {
    service.connect(
      baseUrl: 'https://api.veil.test',
      accessToken: token,
      onEvent: (event, payload) => events.add((event, payload)),
      onConnectionChanged: connectionChanges.add,
    );
  }
}

const _keyDistribution = <String, dynamic>{
  'conversationId': 'group-1',
  'epoch': 3,
  'fromUserId': 'user-2',
  'fromDeviceId': 'device-2',
  'encryptedChainKey': 'sealed-chain-key',
  'nonce': 'nonce-1',
  'version': 'veil-group-v1',
};

void main() {
  test(
      'registers every contract event incl. group.key.distribution, '
      'group.epoch.bumped, conversation.timer.changed', () {
    final harness = _Harness()..connect();

    expect(harness.socket.handlers.keys.toSet(), kRealtimeEventNames);
    expect(
      harness.socket.handlers.keys,
      containsAll(<String>[
        'group.key.distribution',
        'group.epoch.bumped',
        'conversation.timer.changed',
      ]),
    );
    expect(harness.socket.connectCount, 1);
    expect(harness.socketUrls.single, 'https://api.veil.test');
    expect(harness.socketOptions.single['auth'], {'token': 'token-1'});
    expect(harness.socketOptions.single['path'], '/v1/realtime');
  });

  test('malformed group.key.distribution dropped without throwing', () {
    final harness = _Harness()..connect();

    harness.socket.deliver('group.key.distribution', {
      ..._keyDistribution,
      'epoch': 'three',
    });
    harness.socket.deliver('group.key.distribution', {
      ..._keyDistribution,
    }..remove('encryptedChainKey'));
    harness.socket.deliver('group.key.distribution', 'not a map');
    harness.socket.deliver('group.key.distribution', null);

    expect(harness.events, isEmpty);
  });

  test('valid payload forwarded unchanged', () {
    final harness = _Harness()..connect();
    final payload = Map<String, dynamic>.of(_keyDistribution);

    harness.socket.deliver('group.key.distribution', payload);

    final (event, forwarded) = harness.events.single;
    expect(event, 'group.key.distribution');
    expect(identical(forwarded, payload), isTrue);
  });

  test('ignored contract events still reach the handler untouched', () {
    final harness = _Harness()..connect();
    final payload = {'messageId': 'm1', 'deletedAt': 'whenever'};

    harness.socket.deliver('message.deleted', payload);

    expect(harness.events.single.$2, same(payload));
  });

  test('connection changes are reported', () {
    final harness = _Harness()..connect();

    harness.socket.connectionListener!(true);
    harness.socket.connectionListener!(false);

    expect(harness.connectionChanges, [true, false]);
  });

  test('pinned adapter used when pins configured', () {
    final pinned = buildPinnedDartIoHttpClient({
      'spki:tNsbXtI0gVw80AwhaKT80P196yi3fO+WjXBfmligOE8=',
    })!;
    addTearDown(() => pinned.close(force: true));
    final harness = _Harness(httpClientFactory: () => pinned)..connect();

    final options = harness.socketOptions.single;
    final adapter = options['httpClientAdapter'];
    expect(adapter, isA<PinnedSocketHttpClientAdapter>());
    expect((adapter as PinnedSocketHttpClientAdapter).client, same(pinned));
    // A fresh manager per connection, so a cached one cannot bypass the pin.
    expect(options['forceNew'], isTrue);
  });

  test('platform trust is kept when no pins are configured', () {
    final injected = _Harness()..connect();
    expect(injected.socketOptions.single.containsKey('httpClientAdapter'), isFalse);

    // The default factory reads VeilConfig.tlsPins, which tests leave empty.
    final options = <Map<String, dynamic>>[];
    RealtimeService(
      socketFactory: (url, opts) {
        options.add(opts);
        return _FakeSocket();
      },
    ).connect(
      baseUrl: 'https://api.veil.test',
      accessToken: 't',
      onEvent: (_, __) {},
    );
    expect(options.single.containsKey('httpClientAdapter'), isFalse);
  });

  test('updateAuth reconnects with new token', () {
    final harness = _Harness()..connect(token: 'token-1');

    harness.service.updateAuth('token-2');

    expect(harness.socketOptions, hasLength(1), reason: 'same socket, same subscriptions');
    expect(harness.socket.authHistory.last, {'token': 'token-2'});
    expect(harness.socket.disconnectCount, 1);
    expect(harness.socket.connectCount, 2);
    expect(harness.socket.disposed, isFalse);
    expect(harness.service.isConnected, isTrue);
  });

  test('updateAuth before connect is a no-op', () {
    final harness = _Harness();

    harness.service.updateAuth('token-2');

    expect(harness.socketOptions, isEmpty);
  });

  test('disconnect disposes the socket and closes the pinned client', () {
    final httpClient = _RecordingHttpClient();
    final harness = _Harness(httpClientFactory: () => httpClient)..connect();

    harness.service.disconnect();

    expect(harness.socket.disposed, isTrue);
    expect(httpClient.closed, isTrue);
    expect(harness.service.isConnected, isFalse);
  });
}
