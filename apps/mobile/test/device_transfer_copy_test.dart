import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// Completing a transfer revokes the old device in the same transaction
// (DeviceTransferService.complete), which signs it out and wipes its local
// state, and no history moves: the new device registers a fresh identity.
// The transfer screen must say so on both devices, where each decides (the
// new device above its "complete" button, the old one above its approve
// button), and must not promise that the old device stays trusted.
void main() {
  test('the transfer screen says the old device is signed out and history stays behind', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final text in [en.deviceTransferNewCompleteNote, en.deviceTransferApproveFooter]) {
      expect(text, contains('signed out'));
      expect(text, anyOf(contains('history is not transferred'), contains('history does not move')));
      expect(text, isNot(contains('remains trusted')));
    }
    expect(en.deviceTransferComplete, contains('old phone is signed out'));
    expect(en.deviceTransferComplete, isNot(contains('joined the trusted graph')));
  });
}
