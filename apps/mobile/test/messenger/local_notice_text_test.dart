import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/decrypt_status_view.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/local_notice.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

void main() {
  test('group member changes render as their notice text, in both languages', () {
    for (final locale in const [Locale('en'), Locale('ko')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final (added, text) in [(true, l10n.chatNoticeGroupMemberAdded), (false, l10n.chatNoticeGroupMemberRemoved)]) {
        final notice = memberChangeNotice(
          'grp',
          added: added,
          userId: 'user-mallory',
          change: '2',
          conversationMessages: const [],
          now: DateTime.utc(2026, 11, 12),
        );
        expect(notice.message.isLocalNotice, isTrue);
        expect(systemNoticeText(l10n, notice.message, notice.code), text);
      }
    }
  });

  test('the same change of the same member is one notice; another change is another', () {
    LocalNotice added(String change) => memberChangeNotice(
          'grp',
          added: true,
          userId: 'user-mallory',
          change: change,
          conversationMessages: const [],
          now: DateTime.utc(2026, 11, 12),
        );

    expect(added('2').message.id, added('2').message.id);
    expect(added('2').message.id, isNot(added('4').message.id));
  });
}
