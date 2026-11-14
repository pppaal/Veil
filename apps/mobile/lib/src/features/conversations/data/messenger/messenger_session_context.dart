import '../../../../app/app_session_state.dart';
import '../../../../core/config/veil_config.dart';
import 'conversation_peer_bindings.dart' show ConversationPeer;
import 'session_change.dart';

/// The signed-in identity in the shape every relay request needs it.
typedef AuthedSession = ({String accessToken, String userId, String deviceId, String handle});

/// The session the messenger currently runs under, shared by its services.
class MessengerSessionContext {
  AppSessionState _current = const AppSessionState();
  bool _closed = false;
  int _generation = 0;

  /// Bumped whenever the identity goes away or changes. Relay work started
  /// under an earlier generation belongs to an identity that is gone, and
  /// must not change the state once it completes.
  int get generation => _generation;

  AppSessionState get current => _current;

  /// Whether the messenger was disposed. Work already in flight may still
  /// finish, but must start nothing new.
  bool get isClosed => _closed;

  void close() => _closed = true;

  bool get isAuthenticated => _current.isAuthenticated;

  String? get userId => _current.userId;

  String? get deviceId => _current.deviceId;

  /// Adopts [next] and says what changed for the messenger since the
  /// session applied before it.
  SessionChange diff(AppSessionState next) {
    final change = classifySessionChange(_current, next);
    _current = next;
    if (change == SessionChange.signedOut || change == SessionChange.identityChanged) _generation += 1;
    return change;
  }

  /// The session when it is authenticated, whether or not a relay is
  /// configured; null otherwise.
  AuthedSession? get signedIn {
    if (_current
        case AppSessionState(
          accessToken: final String accessToken,
          userId: final String userId,
          deviceId: final String deviceId,
          handle: final String handle,
        )) {
      return (accessToken: accessToken, userId: userId, deviceId: deviceId, handle: handle);
    }
    return null;
  }

  /// The signed-in user as a 1:1 would list them, for the holds of
  /// ConversationPeerBindings; null when signed out.
  ConversationPeer? get selfPeer => switch (signedIn) {
        final session? => ConversationPeer(userId: session.userId, handle: session.handle),
        null => null,
      };

  /// [signedIn] when the relay is configured: what every relay request needs.
  AuthedSession? get authed => VeilConfig.hasApi ? signedIn : null;

  /// [authed], or the error every relay-bound action fails with without it.
  AuthedSession requireAuthed() => authed ?? (throw StateError('Authenticated API session required.'));
}
