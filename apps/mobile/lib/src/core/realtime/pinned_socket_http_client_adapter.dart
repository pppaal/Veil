import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Opens the realtime WebSocket through a pinned [HttpClient].
///
/// socket.io's default adapter connects with a fresh, unpinned client, so a
/// mis-issued certificate would see the bearer token in the handshake.
/// Routing the upgrade through [client] applies the same pins as the API.
/// This is scoped to the socket on purpose: HttpOverrides.global would also
/// silently change every other HttpClient in the process.
class PinnedSocketHttpClientAdapter implements io.HttpClientAdapter {
  PinnedSocketHttpClientAdapter(this.client);

  final HttpClient client;

  @override
  Future<WebSocket> connect(String uri, {Map<String, dynamic>? headers}) {
    return WebSocket.connect(uri, headers: headers, customClient: client);
  }
}
