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
          .disableAutoConnect()
          .setAuth({'token': accessToken})
          .build(),
    );

    _socket!.onConnect((_) => onConnectionChanged?.call(true));
    _socket!.onDisconnect((_) => onConnectionChanged?.call(false));
    _socket!.onReconnect((_) => onConnectionChanged?.call(true));
    _socket!.onReconnectAttempt((_) => onConnectionChanged?.call(false));
    _socket!.onError((_) => onConnectionChanged?.call(false));

    for (final event in const [
      'message.new',
      'message.delivered',
      'message.read',
      'presence.update',
      'conversation.sync',
    ]) {
      _socket!.on(event, (payload) => onEvent(event, payload));
    }

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
