import 'package:socket_io_client/socket_io_client.dart' as io;

/// The slice of a socket.io client that [RealtimeService] drives, so tests
/// can substitute a socket without a server.
abstract interface class RealtimeSocket {
  bool get connected;

  /// Credentials sent in the connect packet of the next (re)connection.
  set auth(Map<String, dynamic> value);

  void on(String event, void Function(dynamic payload) handler);

  /// Reports every transition between connected and not connected,
  /// including reconnection attempts and errors.
  void onConnectionChanged(void Function(bool connected) listener);

  void emit(String event, Map<String, dynamic> payload);

  void connect();

  void disconnect();

  /// Disconnects and drops every listener.
  void dispose();
}

typedef RealtimeSocketFactory = RealtimeSocket Function(
  String url,
  Map<String, dynamic> options,
);

class SocketIoRealtimeSocket implements RealtimeSocket {
  SocketIoRealtimeSocket(this._socket);

  factory SocketIoRealtimeSocket.open(
    String url,
    Map<String, dynamic> options,
  ) {
    return SocketIoRealtimeSocket(io.io(url, options));
  }

  final io.Socket _socket;

  @override
  bool get connected => _socket.connected;

  @override
  set auth(Map<String, dynamic> value) => _socket.auth = value;

  @override
  void on(String event, void Function(dynamic payload) handler) {
    _socket.on(event, handler);
  }

  @override
  void onConnectionChanged(void Function(bool connected) listener) {
    _socket
      ..onConnect((_) => listener(true))
      ..onDisconnect((_) => listener(false))
      ..onReconnect((_) => listener(true))
      ..onReconnectAttempt((_) => listener(false))
      ..onReconnectError((_) => listener(false))
      ..onReconnectFailed((_) => listener(false))
      ..onConnectError((_) => listener(false))
      ..onError((_) => listener(false));
  }

  @override
  void emit(String event, Map<String, dynamic> payload) {
    _socket.emit(event, payload);
  }

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();
}
