import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/veil_config.dart';
import '../network/pinned_http_client.dart';
import 'pinned_socket_http_client_adapter.dart';
import 'realtime_events.dart';
import 'realtime_socket.dart';

/// Builds the pinned client the WebSocket upgrade goes through, or returns
/// null to use the platform trust store.
typedef PinnedHttpClientFactory = HttpClient? Function();

class RealtimeService {
  RealtimeService({
    PinnedHttpClientFactory? httpClientFactory,
    RealtimeSocketFactory? socketFactory,
  })  : _httpClientFactory = httpClientFactory ?? _configuredPinnedClient,
        _socketFactory = socketFactory ?? SocketIoRealtimeSocket.open;

  final PinnedHttpClientFactory _httpClientFactory;
  final RealtimeSocketFactory _socketFactory;
  RealtimeSocket? _socket;
  HttpClient? _pinnedClient;

  bool get isConnected => _socket?.connected ?? false;

  /// Connects and subscribes to every contract event. Payloads of typed
  /// events are validated first: malformed ones are dropped here so handlers
  /// never see them, valid ones reach [onEvent] unchanged.
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    disconnect();
    final pinnedClient = _httpClientFactory();
    _pinnedClient = pinnedClient;
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/v1/realtime')
        // A fresh manager per connection, so the adapter below is the one
        // used rather than whatever a cached manager was built with.
        .enableForceNew()
        .enableReconnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setTimeout(8000)
        .disableAutoConnect()
        .setAuth({'token': accessToken});
    if (pinnedClient != null) {
      options.setHttpClientAdapter(PinnedSocketHttpClientAdapter(pinnedClient));
    }

    final socket = _socketFactory(baseUrl, options.build());
    _socket = socket;
    if (onConnectionChanged != null) {
      socket.onConnectionChanged(onConnectionChanged);
    }
    for (final event in kRealtimeEventNames) {
      socket.on(event, (payload) {
        if (RealtimeEvent.tryParse(event, payload) != null) {
          onEvent(event, payload);
        }
      });
    }
    socket.connect();
  }

  /// Swaps the bearer token on the live socket and reconnects it, keeping
  /// the subscriptions. Use after a token refresh instead of [connect], which
  /// tears everything down.
  void updateAuth(String token) {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket
      ..auth = {'token': token}
      ..disconnect()
      ..connect();
  }

  void emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _pinnedClient?.close(force: true);
    _pinnedClient = null;
  }
}

HttpClient? _configuredPinnedClient() {
  return buildPinnedDartIoHttpClient(parsePinList(VeilConfig.tlsPins));
}
