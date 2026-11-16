import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/decrypt_status_view.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_time.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// A chat held for its handle (listed under @sam with another account than
// the one this phone talked to) admits no identity until the user confirms
// the account, so what that account sent stays locked. Its bubbles say what
// they wait for: the account, which the banner above asks about. Nothing
// about a safety number changed there, so they do not send the user to
// one; a real key change still does.

final _en = lookupAppLocalizations(const Locale('en'));

Future<void> _pumpLine(WidgetTester tester, DecryptStatus status, {required bool heldAccount}) {
  return tester.pumpWidget(MaterialApp(
    theme: VeilTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: DecryptFailureLine(status: status, heldAccount: heldAccount)),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('a refused message in a held chat waits for the account to be confirmed', (tester) async {
    await _pumpLine(tester, DecryptStatus.identityRejected, heldAccount: true);
    expect(find.text('Locked until you confirm this account'), findsOneWidget);
    expect(find.text(_en.chatDecryptIdentityRejected), findsNothing);
  });

  testWidgets('a refused message elsewhere waits for the new safety number to be reviewed', (tester) async {
    await _pumpLine(tester, DecryptStatus.identityRejected, heldAccount: false);
    expect(find.text('Locked until you review the new safety number'), findsOneWidget);
    expect(find.text(_en.chatDecryptHeldAccount), findsNothing);
  });

  testWidgets('a hold changes no other reason a message did not open', (tester) async {
    for (final (status, text) in [
      (DecryptStatus.awaitingKey, _en.chatDecryptAwaitingKey),
      (DecryptStatus.replayed, _en.chatDecryptReplayed),
      (DecryptStatus.failed, _en.chatDecryptFailed),
    ]) {
      await _pumpLine(tester, status, heldAccount: true);
      expect(find.text(text), findsOneWidget, reason: '$status');
      expect(find.text(_en.chatDecryptHeldAccount), findsNothing, reason: '$status');
    }
  });

  testWidgets('the held chat shows the banner and only that account\'s locked messages', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$chatConversationId',
      attention: const ChatAttention(accountHeld: true),
      body: (world) async {
        expect(find.text(_en.chatAccountHoldOtherTitle), findsOneWidget);
        final locked = find.text('Locked until you confirm this account');
        expect(locked, findsNWidgets(heldAccountLineCount));
        for (final element in locked.evaluate()) {
          expect(find.ancestor(of: find.byWidget(element.widget), matching: find.byType(MessageBubble)), findsOneWidget);
        }
        expect(find.text(_en.chatDecryptIdentityRejected), findsNothing);
        // It is another conversation than the one with the Sam this phone
        // knows: none of his messages are in it.
        expect(find.text(latestChatLine), findsNothing);
        expect(find.text(legacyMessageBody), findsNothing);
      },
    );
  });

  // A key change is a safety number matter: the lock line says so there.
  testWidgets('a bubble refused outside a held chat names the safety number', (tester) async {
    final message = ChatMessage(
      id: 'm1',
      senderDeviceId: 'dev-$peerHandle',
      sentAt: DateTime.utc(2026, 4, 7, 9, 52),
      envelope: const CryptoEnvelope(
        version: 'v2',
        conversationId: chatConversationId,
        senderDeviceId: 'dev-$peerHandle',
        recipientUserId: 'user-$selfHandle',
        ciphertext: 'c',
        nonce: 'n',
        messageKind: MessageKind.text,
      ),
    );
    Future<void> pumpBubble({required bool heldAccount}) => tester.pumpWidget(MaterialApp(
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              highlighted: false,
              heldAccount: heldAccount,
              sentAtFormat: MessageTimeFormat(_en, use24HourFormat: false),
              decryptFuture: Future.value(const DecryptedMessage(
                body: '',
                messageKind: MessageKind.text,
                status: DecryptStatus.identityRejected,
              )),
              onResolveAttachment: (_) async {},
              onCancelAttachment: null,
              isResolvingAttachment: (_) => false,
              attachmentDownloadError: (_) => null,
              transferSnapshot: null,
              expiryNow: () => DateTime.utc(2026, 4, 7, 10),
            ),
          ),
        ));

    await pumpBubble(heldAccount: false);
    await tester.pump();
    expect(find.text(_en.chatDecryptIdentityRejected), findsOneWidget);

    await pumpBubble(heldAccount: true);
    await tester.pump();
    expect(find.text(_en.chatDecryptHeldAccount), findsOneWidget);
  });
}
