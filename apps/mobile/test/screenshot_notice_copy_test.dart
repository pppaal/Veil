import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// The chat room shows its screenshot toast at once and sends the peer's
// notice afterwards, without waiting for it (ChatRoomScreen
// _handlePlatformSecurityEvent). The toast must not say the other side was
// already told: the send may still fail, or never leave an offline device.
void main() {
  test('the screenshot toast says a notice is on its way, not that it arrived', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.chatScreenshotToast, contains('a notice is being sent'));
    expect(en.chatScreenshotToast, isNot(contains('has been notified')));

    final ko = lookupAppLocalizations(const Locale('ko'));
    expect(ko.chatScreenshotToast, contains('알림을 보내는 중'));
    expect(ko.chatScreenshotToast, isNot(contains('전송되었습니다')));
  });
}
