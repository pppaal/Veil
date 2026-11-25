import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_risk_line.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_time.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The line under a message the checks on this phone flagged (2.5): under
// the bubble, after the legacy sender line, a 14 dp glyph and the reason
// in small type, muted for mild, in the warning colour for warn and the
// danger colour for strong, three lines at most, read out as its words.

final AppLocalizations l10n = AppLocalizationsEn();

ChatMessage _message({bool mine = false}) => ChatMessage(
      id: 'msg-1',
      senderDeviceId: 'device-1',
      sentAt: DateTime(2026, 4, 7, 9, 17),
      isMine: mine,
      envelope: const CryptoEnvelope(
        version: 'v',
        conversationId: 'conv-1',
        senderDeviceId: 'device-1',
        recipientUserId: 'user-1',
        ciphertext: 'x',
        nonce: 'n',
        messageKind: MessageKind.text,
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  required MessageRisk risk,
  bool mine = false,
  DecryptStatus status = DecryptStatus.ok,
  String body = 'send me the code you just got, quick',
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: VeilTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: MessageBubble(
            message: _message(mine: mine),
            conversationId: 'conv-1',
            highlighted: false,
            sentAtFormat: MessageTimeFormat(AppLocalizationsEn(), use24HourFormat: true),
            decryptFuture: Future.value(DecryptedMessage(body: body, messageKind: MessageKind.text, status: status)),
            onCancelAttachment: null,
            transferSnapshot: null,
            expiryNow: () => DateTime(2026, 4, 7, 9, 18),
            risk: risk,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('the risk line sits under the bubble in the tone of its level', (tester) async {
    final palette = VeilPalette.dark;
    final cases = [
      (RiskLevel.mild, Icons.info_outline, palette.textMuted),
      (RiskLevel.warn, Icons.warning_amber_outlined, palette.warning),
      (RiskLevel.strong, Icons.error_outline, palette.danger),
    ];
    for (final (level, icon, colour) in cases) {
      await _pump(tester, risk: MessageRisk(level: level, reason: RiskReason.asksForCode));
      final line = find.text(l10n.riskLineCode);
      expect(line, findsOneWidget, reason: '$level: one line');
      expect(find.byType(MessageRiskLine), findsOneWidget);
      expect(tester.getRect(line).top, greaterThanOrEqualTo(tester.getRect(find.byType(VeilBubble)).bottom),
          reason: '$level: under the bubble, not in it');
      expect(find.descendant(of: find.byType(VeilBubble), matching: find.byType(MessageRiskLine)), findsNothing);
      final text = tester.widget<Text>(line);
      expect(text.style?.color, colour, reason: '$level: its colour');
      expect(text.maxLines, 3);
      final glyph = tester.widget<Icon>(find.descendant(of: find.byType(MessageRiskLine), matching: find.byType(Icon)));
      expect(glyph.icon, icon, reason: '$level: its glyph');
      expect(glyph.size, 14);
      expect(glyph.color, colour);
      // The glyph sits beside the first line of the words.
      expect(tester.getRect(find.byIcon(icon)).right, lessThan(tester.getRect(line).left));
    }

    // Read out as its words.
    final semantics = tester.ensureSemantics();
    await _pump(tester, risk: const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney));
    expect(find.bySemanticsLabel(l10n.riskLineMoney), findsOneWidget);
    semantics.dispose();

    // A message from an older version: its sender line first, then the risk line.
    await _pump(
      tester,
      risk: const MessageRisk(level: RiskLevel.strong, reason: RiskReason.fakeAuthority),
      status: DecryptStatus.legacyUnauthenticated,
    );
    final legacy = tester.getRect(find.text(l10n.chatLegacySenderLine));
    final risk = tester.getRect(find.text(l10n.riskLineAuthority));
    expect(risk.top, greaterThanOrEqualTo(legacy.bottom));

    // Never on the user's own message, and none for a clean one.
    await _pump(tester, risk: const MessageRisk(level: RiskLevel.strong, reason: RiskReason.asksForCode), mine: true);
    expect(find.byType(MessageRiskLine), findsNothing);
    expect(find.text(l10n.riskLineCode), findsNothing);
    await _pump(tester, risk: MessageRisk.none);
    expect(find.byType(MessageRiskLine), findsNothing);

    // The longest reason at the narrowest width keeps to three lines.
    await _pump(tester, risk: const MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim));
    final long = tester.getRect(find.text(l10n.riskLineNewPhoneClaim));
    final lineHeight = tester.widget<Text>(find.text(l10n.riskLineNewPhoneClaim)).style!.fontSize! * 2;
    expect(long.height, lessThan(lineHeight * 3));
    expect(tester.takeException(), isNull);
  });
}
