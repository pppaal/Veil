enum AuthFlowStage {
  idle('Idle'),
  generatingKeys('Generating local identity'),
  registering('Registering handle'),
  requestingChallenge('Requesting challenge'),
  verifying('Verifying device'),
  complete('Bound');

  const AuthFlowStage(this.label);

  final String label;
}

class AppSessionState {
  static const Object _unset = Object();

  const AppSessionState({
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.deviceId,
    this.handle,
    this.displayName,
    this.onboardingAccepted = false,
    this.privacyConsentAccepted = false,
    this.locked = true,
    this.initializing = true,
    this.authFlowStage = AuthFlowStage.idle,
    this.errorMessage,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final String? deviceId;
  final String? handle;
  final String? displayName;
  final bool onboardingAccepted;
  final bool privacyConsentAccepted;
  final bool locked;
  final bool initializing;
  final AuthFlowStage authFlowStage;
  final String? errorMessage;

  bool get isAuthenticated =>
      accessToken != null &&
      userId != null &&
      deviceId != null &&
      handle != null;

  bool get isAuthenticating =>
      authFlowStage != AuthFlowStage.idle &&
      authFlowStage != AuthFlowStage.complete;

  AppSessionState copyWith({
    Object? accessToken = _unset,
    Object? refreshToken = _unset,
    Object? userId = _unset,
    Object? deviceId = _unset,
    Object? handle = _unset,
    Object? displayName = _unset,
    bool? onboardingAccepted,
    bool? privacyConsentAccepted,
    bool? locked,
    bool? initializing,
    AuthFlowStage? authFlowStage,
    Object? errorMessage = _unset,
  }) {
    return AppSessionState(
      accessToken: identical(accessToken, _unset)
          ? this.accessToken
          : accessToken as String?,
      refreshToken: identical(refreshToken, _unset)
          ? this.refreshToken
          : refreshToken as String?,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      deviceId:
          identical(deviceId, _unset) ? this.deviceId : deviceId as String?,
      handle: identical(handle, _unset) ? this.handle : handle as String?,
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
      onboardingAccepted: onboardingAccepted ?? this.onboardingAccepted,
      privacyConsentAccepted: privacyConsentAccepted ?? this.privacyConsentAccepted,
      locked: locked ?? this.locked,
      initializing: initializing ?? this.initializing,
      authFlowStage: authFlowStage ?? this.authFlowStage,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
