import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeService {
  io.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    disconnect();
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/v1/realtime')
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(8000)
          .disableAutoConnect()
          .setAuth({'token': accessToken})
          .build(),
    );

    _socket!.onConnect((_) => onConnectionChanged?.call(true));
    _socket!.onDisconnect((_) => onConnectionChanged?.call(false));
    _socket!.onReconnect((_) => onConnectionChanged?.call(true));
    _socket!.onReconnectAttempt((_) => onConnectionChanged?.call(false));
    _socket!.onReconnectError((_) => onConnectionChanged?.call(false));
    _socket!.onReconnectFailed((_) => onConnectionChanged?.call(false));
    _socket!.onConnectError((_) => onConnectionChanged?.call(false));
    _socket!.onError((_) => onConnectionChanged?.call(false));

    for (final event in const [
      'message.new',
      'message.delivered',
      'message.read',
      'message.reaction',
      'presence.update',
      'typing.start',
      'typing.stop',
      'conversation.sync',
    ]) {
      _socket!.on(event, (payload) => onEvent(event, payload));
    }

    _socket!.connect();
  }

  void emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
