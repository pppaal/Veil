import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// Completing a transfer revokes the old device in the same transaction
// (DeviceTransferService.complete), which signs it out and wipes its local
// state, and no history moves: the new device registers a fresh identity.
// The transfer screen must say so, and must not promise that the old device
// stays trusted.
void main() {
  test('the transfer screen says the old device is signed out and history stays behind', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final text in [en.deviceTransferHeroBody, en.deviceTransferCompleteOnNewNote]) {
      expect(text, contains('signed out'));
      expect(text, anyOf(contains('history is not transferred'), contains('history does not move')));
      expect(text, isNot(contains('remains trusted')));
    }
    expect(en.deviceTransferComplete, contains('old device has been signed out'));
    expect(en.deviceTransferComplete, isNot(contains('joined the trusted graph')));

    final ko = lookupAppLocalizations(const Locale('ko'));
    for (final text in [ko.deviceTransferHeroBody, ko.deviceTransferCompleteOnNewNote]) {
      expect(text, contains('로그아웃'));
      expect(text, contains('대화 기록은'));
      expect(text, isNot(contains('계속 신뢰됩니다')));
    }
    expect(ko.deviceTransferComplete, contains('로그아웃'));
  });
}
