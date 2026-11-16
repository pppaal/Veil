import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// Completing a transfer revokes the old device in the same transaction
// (DeviceTransferService.complete), which signs it out and wipes its local
// state, and no history moves: the new device registers a fresh identity.
// The old phone's approve dialog, where the move is decided, must say so,
// and nothing may promise that the old device stays trusted.
void main() {
  test('the approve dialog says the old phone is signed out and the messages stay behind', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final body = en.deviceTransferApproveBody('ab12');
    expect(body, contains('signed out'));
    expect(body, contains("messages won't move"));
    expect(body, contains('ab12'), reason: 'the key fingerprint the new phone shows');
    for (final text in [body, en.deviceTransferComplete]) {
      expect(text, isNot(contains('remains trusted')));
      expect(text, isNot(contains('joined the trusted graph')));
    }
  });
}
