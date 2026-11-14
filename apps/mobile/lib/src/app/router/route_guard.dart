import '../../core/config/veil_config.dart';
import '../app_session_state.dart';

const _splashPath = '/splash';
const _privacyConsentPath = '/privacy-consent';
const _onboardingPath = '/onboarding';
const _createAccountPath = '/create-account';
const _lockPath = '/lock';
const _homePath = '/conversations';
const _returnParameter = 'from';

/// Where a signed-out device may be.
const _signedOutPaths = <String>{
  _splashPath,
  _createAccountPath,
  '/choose-handle',
  '/device-transfer',
};

/// Gate screens a signed-in, unlocked user is sent past. Never worth
/// returning to after an unlock.
const _gatePaths = <String>{
  _splashPath,
  _privacyConsentPath,
  _onboardingPath,
  _createAccountPath,
  '/choose-handle',
  _lockPath,
};

/// The part of the session that decides where the user may be. Anything else
/// (tokens above all) changing must not re-run redirects, or a routine token
/// refresh would yank the user out of the screen they are on.
class RouteGuardState {
  const RouteGuardState({
    required this.initializing,
    required this.configurationError,
    required this.authenticated,
    required this.locked,
    required this.privacyConsentAccepted,
    required this.onboardingAccepted,
  });

  factory RouteGuardState.fromSession(AppSessionState session) {
    return RouteGuardState(
      initializing: session.initializing,
      // Only an unusable build configuration pins the app to the splash
      // error. Flow errors (a taken handle, an expired transfer) are shown
      // inline by the screen that raised them.
      configurationError: VeilConfig.runtimeConfigurationError != null,
      authenticated: session.isAuthenticated,
      locked: session.locked,
      privacyConsentAccepted: session.privacyConsentAccepted,
      onboardingAccepted: session.onboardingAccepted,
    );
  }

  final bool initializing;
  final bool configurationError;
  final bool authenticated;
  final bool locked;
  final bool privacyConsentAccepted;
  final bool onboardingAccepted;

  /// A signed-in session behind the local barrier.
  bool get lockedOut => authenticated && locked;

  @override
  bool operator ==(Object other) {
    return other is RouteGuardState &&
        other.initializing == initializing &&
        other.configurationError == configurationError &&
        other.authenticated == authenticated &&
        other.locked == locked &&
        other.privacyConsentAccepted == privacyConsentAccepted &&
        other.onboardingAccepted == onboardingAccepted;
  }

  @override
  int get hashCode => Object.hash(
        initializing,
        configurationError,
        authenticated,
        locked,
        privacyConsentAccepted,
        onboardingAccepted,
      );
}

/// The location to send the user to instead of [uri], or null to stay.
///
/// Locking keeps the interrupted location in `?from=` so unlocking returns
/// there rather than to the conversation list.
String? redirectFor(RouteGuardState state, Uri uri) {
  final path = uri.path;
  if (state.initializing || state.configurationError) {
    return path == _splashPath ? null : _splashPath;
  }
  if (state.lockedOut) {
    return path == _lockPath ? null : _lockLocation(interrupted: uri);
  }
  if (!state.privacyConsentAccepted) {
    return path == _privacyConsentPath ? null : _privacyConsentPath;
  }
  if (!state.onboardingAccepted) {
    return path == _onboardingPath ? null : _onboardingPath;
  }
  if (!state.authenticated) {
    return _signedOutPaths.contains(path) ? null : _createAccountPath;
  }
  if (path == _lockPath) {
    return _returnLocation(uri.queryParameters[_returnParameter]) ?? _homePath;
  }
  if (_gatePaths.contains(path)) {
    return _homePath;
  }
  return null;
}

/// Whether unlocking at [lockLocation] goes back to [interrupted], the
/// location the lock replaced, rather than to a destination requested while
/// locked (say, a notification tap that redirected to the lock). A gate
/// screen (the cold-start splash above all) is never worth going back to:
/// the redirect would only move past it again.
bool resumesInterruptedLocation(Uri lockLocation, Uri interrupted) {
  if (lockLocation.path != _lockPath || _gatePaths.contains(interrupted.path)) {
    return false;
  }
  final returnTo = lockLocation.queryParameters[_returnParameter];
  return returnTo == null || returnTo == interrupted.toString();
}

String _lockLocation({required Uri interrupted}) {
  if (_gatePaths.contains(interrupted.path)) {
    return _lockPath;
  }
  return Uri(
    path: _lockPath,
    queryParameters: {_returnParameter: interrupted.toString()},
  ).toString();
}

/// Accepts only in-app paths: a value like `//evil.example` or a full URL
/// must never become a navigation target, and returning to the lock (or any
/// other gate) would loop.
String? _returnLocation(String? candidate) {
  if (candidate == null ||
      !candidate.startsWith('/') ||
      candidate.startsWith('//')) {
    return null;
  }
  final parsed = Uri.tryParse(candidate);
  if (parsed == null || parsed.hasScheme || _gatePaths.contains(parsed.path)) {
    return null;
  }
  return candidate;
}
