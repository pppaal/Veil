import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeService {
  io.Socket? _socket;

  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
  }) {
    disconnect();
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/v1/realtime')
          .disableAutoConnect()
          .setAuth({'token': accessToken})
          .build(),
    );

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
