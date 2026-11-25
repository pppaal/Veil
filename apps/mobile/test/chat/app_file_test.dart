import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_risk_line.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/media_receive_seed.dart';
import '../phone/phone_app.dart';
import '../support/fake_attachment_opener.dart';
import '../support/layout_trust.dart';

// An Android app sent as a file (.apk, .xapk, .apks; 2.6, section 8 item
// 9): its line under the bubble says it is an app file, whoever sent it (in
// the tone of the sender's relationship), and opening or saving it goes
// through the strong sheet first, with staying away the filled button.
// Nothing is fetched until the user goes on.

final Uint8List _apk = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List<int>.filled(4096, 0x41)]);
const _apkType = 'application/vnd.android.package-archive';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  late FakeAttachmentOpener opener;
  final en = lookupAppLocalizations(const Locale('en'));
  final receivedFile = find.byWidgetPredicate((widget) => widget is MessageFileCard && !widget.message.isMine);
  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  setUp(() => opener = FakeAttachmentOpener());

  // Files, isolates and decodes run on real time only.
  Future<void> until(WidgetTester tester, bool Function() done, {String? reason}) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done(), isTrue, reason: reason);
    await pumpFrames(tester, frames: 3);
  }

  MessageRisk lineOf(WidgetTester tester) => tester.widget<MessageRiskLine>(find.byType(MessageRiskLine)).risk;

  testWidgets('an app file gets the app-file line from any sender, and opening or saving it asks first', (tester) async {
    // A stranger's app file: the strongest line.
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/conv-mallory',
      overrides: [attachmentOpenerProvider.overrideWithValue(opener)],
      beforeSession: (relay) => addStranger(relay, identities, 'mallory'),
      afterSession: (world) async {
        await attachContactTrust(world);
        world.relay.addDirect('conv-mallory', selfHandle, 'mallory');
        await world.messenger.refreshConversations();
        await deliverAttachment(world,
            plaintext: _apk,
            contentType: _apkType,
            kind: MessageKind.file,
            body: 'Bank-Security.apk',
            conversationId: 'conv-mallory',
            from: 'mallory',
            hour: 10,
            minute: 12);
      },
      body: (world) async {
        await pumpFrames(tester, frames: 6);
        expect(find.text(en.riskLineAppFileAttached), findsOneWidget);
        expect(lineOf(tester), const MessageRisk(level: RiskLevel.strong, reason: RiskReason.appFile));

        await tester.tap(receivedFile);
        await pumpFrames(tester, frames: 6);
        expect(inSheet(find.text(en.fileRiskAppTitle)), findsOneWidget);
        expect(inSheet(find.text(en.linkRiskAppBody)), findsOneWidget);
        expect(inSheet(find.text('Bank-Security.apk')), findsOneWidget);
        await tester.tap(inSheet(find.widgetWithText(FilledButton, en.linkRiskKeepClosed)));
        await pumpFrames(tester, frames: 4);
        expect(find.byType(BottomSheet), findsNothing);
        expect(world.relay.downloadTicketRequests, isEmpty, reason: 'nothing is fetched before the user goes on');
        expect(opener.opened, isEmpty);
      },
    );

    // A verified contact's: a mild line, and still the strong sheet, for
    // opening and for saving.
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/conv-sam',
      overrides: [attachmentOpenerProvider.overrideWithValue(opener)],
      afterSession: (world) async {
        await attachContactTrust(world);
        await deliverAttachment(world,
            plaintext: _apk, contentType: _apkType, kind: MessageKind.file, body: 'update.apk', hour: 10, minute: 12);
      },
      body: (world) async {
        await pumpFrames(tester, frames: 6);
        expect(find.text(en.riskLineAppFileAttached), findsOneWidget);
        expect(lineOf(tester), const MessageRisk(level: RiskLevel.mild, reason: RiskReason.appFile));

        // Open: the strong sheet; Open anyway fetches and opens it.
        await tester.tap(receivedFile);
        await pumpFrames(tester, frames: 6);
        expect(inSheet(find.text(en.fileRiskAppTitle)), findsOneWidget);
        final openAnyway = tester.widget<VeilRow>(find.byKey(const ValueKey('app-file-go-on')));
        expect(openAnyway.title, en.linkRiskOpenAnyway);
        expect(openAnyway.destructive, isTrue);
        expect(world.relay.downloadTicketRequests, isEmpty);
        await tester.tap(find.byKey(const ValueKey('app-file-go-on')));
        await until(tester, () => opener.opened.isNotEmpty, reason: 'Open anyway did not fetch and open it');
        expect(opener.opened.single.bytes, _apk);

        // Save, from the long-press menu: the strong sheet before the usual
        // question. Don't save saves nothing.
        await tester.longPress(receivedFile);
        await pumpFrames(tester, frames: 4);
        await tester.tap(find.byKey(const ValueKey('message-save')));
        await pumpFrames(tester, frames: 6);
        expect(inSheet(find.text(en.fileRiskAppTitle)), findsOneWidget);
        expect(inSheet(find.widgetWithText(FilledButton, en.fileRiskDontSave)), findsOneWidget);
        await tester.tap(inSheet(find.widgetWithText(FilledButton, en.fileRiskDontSave)));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.chatSaveTitle), findsNothing);
        expect(opener.saved, isEmpty);

        await tester.longPress(receivedFile);
        await pumpFrames(tester, frames: 4);
        await tester.tap(find.byKey(const ValueKey('message-save')));
        await pumpFrames(tester, frames: 6);
        final saveAnyway = tester.widget<VeilRow>(find.byKey(const ValueKey('app-file-go-on')));
        expect(saveAnyway.title, en.fileRiskSaveAnyway);
        expect(saveAnyway.destructive, isTrue);
        await tester.tap(find.byKey(const ValueKey('app-file-go-on')));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.chatSaveTitle), findsOneWidget, reason: 'then the question every save asks');
        await tester.tap(find.byKey(const ValueKey('save-confirm')));
        await until(tester, () => opener.saved.isNotEmpty, reason: 'nothing reached the save screen');
        expect(opener.saved.single.bytes, _apk);
      },
    );
  });
}
