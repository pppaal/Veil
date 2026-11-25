import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/safety/data/abuse_reports.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// A message request on real messengers over the fake relay: what the phone
// holds back while a stranger's chat waits (read receipts, typing, photo
// fetches), what Accept sends, and that a report from a request carries no
// more than any report.

const conv = 'conv-carol';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty carol;

  setUp(() async {
    relay = trustRelay();
    alice = await phone(relay, 'alice', requests: true);
    carol = await phone(relay, 'carol');
    await alice.signIn();
    await carol.signIn();
    // Alice's app is in front and unlocked, as VeilApp reports it.
    alice.controller.media.setInUse(true);
    await trustReady(alice);
    relay.addDirect(conv, 'carol', 'alice');
  });

  tearDown(() async {
    await alice.dispose();
    await carol.dispose();
  });

  // A small photo staged in [party]'s staging folder, as the attach flow
  // leaves it.
  Future<String> stagedPhoto(MessengerParty party, int seed) async {
    final image = img.Image(width: 24, height: 24)..clear(img.ColorRgb8(seed, 80, 160));
    final staging = await party.attachmentPaths.stagingDir();
    final name = 'photo${seed.toRadixString(16).padLeft(30, '0')}';
    return (File(p.join(staging.path, name))..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(image)))).path;
  }

  Future<void> sendPhoto(MessengerParty from, int seed) async {
    final before = alice.controller.messagesFor(conv).length;
    final sent = await from.controller.sendAttachment(
      conversationId: conv,
      attachment: OutgoingAttachment.photo(path: await stagedPhoto(from, seed), contentType: 'image/jpeg'),
    );
    expect(sent, isTrue);
    await waitFor(() => from.controller.pendingCountFor(conv) == 0,
        timeout: const Duration(seconds: 10), reason: 'the photo was not sent');
    await waitFor(() => alice.controller.messagesFor(conv).length > before,
        timeout: const Duration(seconds: 10), reason: 'the photo did not arrive');
  }

  List<String> ticketsOfAlice() => relay.downloadTicketRequestsBy['alice'] ?? const [];

  test('a stranger\'s first message waits as a request: no read receipt, no typing, no photo fetch until accepted', () async {
    await deliver(carol, alice, conv, 'hi alice, it is me');
    await sendPhoto(carol, 1);
    expect(alice.contactTrust.isRequest(conv), isTrue);

    // Alice opens the chat and reads it: the mark moves, no receipt goes.
    alice.controller.setActiveConversation(conv);
    await settle();
    expect(alice.controller.reads.readMarkOf(conv)?.readThrough, isNotNull, reason: 'the chat was not read');
    expect(alice.api.markReadCalls, isEmpty, reason: 'a read receipt went for a request');

    // Typing in the request tells carol nothing.
    alice.controller.notifyTyping(conv);
    expect(alice.realtime.emittedEvents, isNot(contains('typing.start')));

    // The photo waits for a tap.
    await settle(const Duration(milliseconds: 500));
    expect(ticketsOfAlice(), isEmpty, reason: 'a photo in a request was fetched on its own');

    // Once accepted, typing goes, and the next photo is fetched on its own.
    await alice.contactTrust.accept(conv);
    alice.controller.notifyTyping(conv);
    expect(alice.realtime.emittedEvents, contains('typing.start'));
    await sendPhoto(carol, 2);
    await waitFor(() => ticketsOfAlice().isNotEmpty,
        timeout: const Duration(seconds: 10), reason: 'a photo in an accepted chat was not fetched');
  });

  test('accepting a request sends the read receipt for what was read', () async {
    await deliver(carol, alice, conv, 'first');
    await deliver(carol, alice, conv, 'second');
    alice.controller.setActiveConversation(conv);
    await settle();
    expect(alice.api.markReadCalls, isEmpty);

    await alice.contactTrust.accept(conv);
    final newest = alice.controller.messagesFor(conv).lastWhere((message) => !message.isMine && !message.isLocalNotice);
    await waitFor(() => alice.api.markReadCalls.isNotEmpty, reason: 'no receipt went after Accept');
    expect(alice.api.markReadCalls, [newest.id], reason: 'one receipt, for the newest message read');
    await waitFor(
      () => carol.controller.messagesFor(conv).any((message) => message.id == newest.id && message.readAt != null),
      reason: 'carol did not see her message read',
    );

    // Off in settings, nothing goes.
    alice.readReceipts = false;
    await alice.controller.resendReadReceipt(conv);
    expect(alice.api.markReadCalls, hasLength(1));
  });

  test('a report from a request carries the same fields as any report', () async {
    relay.addDirect('conv-bob', 'bob', 'alice');
    final bob = await phone(relay, 'bob');
    addTearDown(bob.dispose);
    await bob.signIn();
    await deliver(carol, alice, conv, 'click this');
    await deliver(bob, alice, 'conv-bob', 'click that');
    await alice.contactTrust.accept('conv-bob');
    expect(alice.contactTrust.isRequest(conv), isTrue);
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);

    final reports = AbuseReports(api: alice.api, accessToken: () => 'token-alice');
    ChatMessage theirs(String id) => alice.controller.messagesFor(id).lastWhere((message) => !message.isMine);
    for (final (id, handle) in [(conv, 'carol'), ('conv-bob', 'bob')]) {
      final target = ReportTarget(
        userId: 'user-$handle',
        handle: handle,
        conversationId: id,
        messageId: theirs(id).id,
        offerBlock: true,
      );
      expect(await reports.file(target, ReportReason.values.first), isTrue);
    }
    final [fromRequest, fromChat] = relay.reports;
    expect(fromRequest.fields.keys.toSet(), fromChat.fields.keys.toSet());
    expect(fromRequest.fields.keys.toSet(), {'reportedUserId', 'reason', 'conversationId', 'messageId'});
    expect(fromRequest.fields['conversationId'], conv);
    expect(fromRequest.fields.values.join(' '), isNot(contains('click')), reason: 'a report quoted the message');
  });
}
