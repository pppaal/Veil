import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/ai/presentation/ai_chat_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_expiration.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

void main() {
  test('formats message expiration in seconds', () {
    final now = DateTime.utc(2026, 3, 27, 10, 0, 0);
    final expiresAt = now.add(const Duration(seconds: 30));

    expect(formatMessageExpiry(expiresAt, now: now), 'Expires in 30s');
  });

  test('marks expired messages as expired', () {
    final now = DateTime.utc(2026, 3, 27, 10, 0, 0);
    final expiresAt = now.subtract(const Duration(seconds: 1));

    expect(isMessageExpired(expiresAt, now: now), isTrue);
  });

  testWidgets('AI screen keeps the scripted-demo disclosure and makes no relay claims',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiChatScreen(),
      ),
    );
    const disclosure = 'Demo: replies are scripted on this device. Nothing is sent anywhere.';
    expect(find.text(disclosure), findsOneWidget);

    for (final question in ['how do group chats work?', 'are calls private?', 'tell me more']) {
      await tester.enterText(find.byType(TextField), question);
      await tester.tap(find.text('Ask'));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
    }

    expect(find.text(disclosure), findsOneWidget);
    expect(find.textContaining('relay fallback'), findsNothing);
    expect(find.textContaining('encrypted relay'), findsNothing);
    expect(find.textContaining('individually'), findsNothing);
  });
}
