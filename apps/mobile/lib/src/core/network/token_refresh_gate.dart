import 'dart:async';

/// Collapses concurrent access-token refreshes into a single refresher call.
///
/// The server consumes refresh tokens atomically and single-use, so when
/// several requests hit 401 together (typically on app resume: a sync, a
/// drain and a fetch at once) only one refresh may run. Every other caller
/// awaits that same refresh and replays with its result.
class TokenRefreshGate {
  TokenRefreshGate(this._refresher);

  final Future<String?> Function() _refresher;
  Future<String?>? _inFlight;
  String? _replacedToken;
  String? _replacementToken;

  /// Returns the token to replay a request that was rejected while carrying
  /// [staleToken], or null when the session cannot be refreshed (the caller
  /// then surfaces its original 401).
  Future<String?> replacementFor(String staleToken) {
    // A 401 that arrives after its token was already rotated must not spend
    // another single-use refresh token.
    if (staleToken == _replacedToken) {
      return Future<String?>.value(_replacementToken);
    }
    return _inFlight ??= _refresh(staleToken);
  }

  Future<String?> _refresh(String staleToken) async {
    try {
      // Future.sync turns a synchronous throw into a failed future, so the
      // `finally` below always runs after `_inFlight` has been assigned.
      final fresh = await Future<String?>.sync(_refresher);
      if (fresh == null || fresh.isEmpty || fresh == staleToken) {
        return null;
      }
      _replacedToken = staleToken;
      _replacementToken = fresh;
      return fresh;
    } catch (_) {
      // A refresh that throws is a refresh that failed: every waiter keeps
      // its original 401 rather than an unrelated error.
      return null;
    } finally {
      _inFlight = null;
    }
  }
}
