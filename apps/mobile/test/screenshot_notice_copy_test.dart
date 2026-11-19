import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/decrypt_status_view.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// A screenshot is a line in the chat on both sides, as Telegram and Session
// do it (ChatRoomScreen _handlePlatformSecurityEvent): the notice sent to
// the others names who took it, and this phone's own copy reads "You took
// a screenshot". Neither says the others were told: the send may still
// fail, or never leave an offline device.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  ChatMessage message({required bool mine}) => ChatMessage(
        id: 'm1',
        senderDeviceId: 'device-1',
        sentAt: DateTime.utc(2026, 4, 7),
        isMine: mine,
        envelope: const CryptoEnvelope(
          version: 'v',
          conversationId: 'c1',
          senderDeviceId: 'device-1',
          recipientUserId: 'u2',
          ciphertext: 'x',
          nonce: 'n',
          messageKind: MessageKind.system,
        ),
      );

  test('the notice names who took the screenshot, and claims nothing about delivery', () {
    expect(en.chatScreenshotSystemNotice('sam'), '@sam took a screenshot');
    for (final line in [en.chatScreenshotSystemNotice('sam'), en.chatScreenshotSelfNotice]) {
      expect(line, isNot(contains('notified')));
      expect(line, isNot(contains('told')));
    }
  });

  test('the sender reads its own notice as "You took a screenshot"; the others read it as sent', () {
    final sent = en.chatScreenshotSystemNotice('sam');
    expect(systemNoticeText(en, message(mine: true), sent), en.chatScreenshotSelfNotice);
    expect(systemNoticeText(en, message(mine: false), sent), sent);
    // Another system line of the user's own stays as it is.
    expect(systemNoticeText(en, message(mine: true), 'Something else'), 'Something else');
  });
}
