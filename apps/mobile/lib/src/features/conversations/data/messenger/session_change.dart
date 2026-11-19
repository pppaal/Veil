import '../../../../app/app_session_state.dart';

enum SessionChange {
  /// Nothing the messenger depends on changed (e.g. lock/unlock).
  none,

  /// No authenticated identity any more.
  signedOut,

  /// A different user, device or handle: every identity-bound cache is stale.
  identityChanged,

  /// Same identity with a new access token, e.g. an automatic refresh.
  tokenOnly,
}

SessionChange classifySessionChange(
  AppSessionState previous,
  AppSessionState next,
) {
  if (!next.isAuthenticated) {
    final changed =
        previous.accessToken != next.accessToken || previous.handle != next.handle;
    return changed ? SessionChange.signedOut : SessionChange.none;
  }
  if (!previous.isAuthenticated ||
      previous.userId != next.userId ||
      previous.deviceId != next.deviceId ||
      previous.handle != next.handle) {
    return SessionChange.identityChanged;
  }
  return previous.accessToken == next.accessToken
      ? SessionChange.none
      : SessionChange.tokenOnly;
}
