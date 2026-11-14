import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/session_change.dart';

const _signedIn = AppSessionState(
  accessToken: 'token-1',
  userId: 'user-1',
  deviceId: 'device-1',
  handle: 'atlas',
  locked: false,
  initializing: false,
);

void main() {
  test('a new access token for the same identity is token-only', () {
    expect(
      classifySessionChange(_signedIn, _signedIn.copyWith(accessToken: 'token-2')),
      SessionChange.tokenOnly,
    );
  });

  test('locking and unlocking with the same identity changes nothing', () {
    final locked = _signedIn.copyWith(locked: true);
    expect(classifySessionChange(_signedIn, locked), SessionChange.none);
    expect(classifySessionChange(locked, _signedIn), SessionChange.none);
  });

  test('unlocking with a refreshed token is token-only', () {
    expect(
      classifySessionChange(
        _signedIn.copyWith(locked: true),
        _signedIn.copyWith(accessToken: 'token-2'),
      ),
      SessionChange.tokenOnly,
    );
  });

  test('a different user, device or handle is an identity change', () {
    expect(classifySessionChange(_signedIn, _signedIn.copyWith(userId: 'user-2')),
        SessionChange.identityChanged);
    expect(classifySessionChange(_signedIn, _signedIn.copyWith(deviceId: 'device-2')),
        SessionChange.identityChanged);
    expect(classifySessionChange(_signedIn, _signedIn.copyWith(handle: 'selene')),
        SessionChange.identityChanged);
  });

  test('the first sign-in is an identity change', () {
    expect(classifySessionChange(const AppSessionState(), _signedIn), SessionChange.identityChanged);
  });

  test('losing the token signs out; staying signed out changes nothing', () {
    expect(
      classifySessionChange(_signedIn, _signedIn.copyWith(accessToken: null)),
      SessionChange.signedOut,
    );
    expect(
      classifySessionChange(const AppSessionState(), const AppSessionState(locked: false)),
      SessionChange.none,
    );
  });
}
