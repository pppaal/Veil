import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/features/safety/application/silenced_notifications.dart';
import 'package:veil_mobile/src/features/safety/data/abuse_reports.dart';
import 'package:veil_mobile/src/features/safety/data/blocked_accounts.dart';
import 'package:veil_mobile/src/features/safety/data/conversation_mutes.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// Blocking, muting and reporting through two real messengers on the fake
// relay, which enforces a block the way the server does: a 1:1 send across
// it is refused in either direction.

const conv = 'conv-ab';

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;
  late DateTime now;
  late ConversationMutes mutes;
  late BlockedAccounts blocked;

  setUp(() async {
    relay = FakeRelay();
    now = DateTime.utc(2026, 11, 16, 9);
    alice = await MessengerParty.join(
      relay,
      handle: 'alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      // Built the way messenger_providers.dart builds it; the app's own
      // wiring is checked in app_notification_filter_test.dart.
      notificationsFor: (recorder) => SilencedNotifications(
        recorder,
        isSilenced: (conversationId) => conversationSilenced(
          conversationId,
          alice.controller.conversationById(conversationId),
          mutes: mutes,
          blocked: blocked,
        ),
      ),
    );
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
    mutes = ConversationMutes(
      store: InMemoryIdentityKeyValueBackend(),
      api: alice.api,
      accessToken: () => 'token-alice',
      clock: () => now,
    );
    blocked = BlockedAccounts(api: alice.api, accessToken: () => 'token-alice');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    mutes.dispose();
    blocked.dispose();
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(MessengerParty from, MessengerParty to, String body) async {
    await from.controller.sendText(conversationId: conv, body: body);
    await waitFor(() => from.controller.pendingCountFor(conv) == 0, reason: '"$body" was not acked');
    await waitFor(() async => (await to.bodies(conv)).contains(body), reason: '"$body" did not arrive');
  }

  ChatMessage ownMessage(MessengerParty party, String clientMessageId) =>
      party.controller.messagesFor(conv).firstWhere((message) => message.clientMessageId == clientMessageId);

  test('a block refuses sends both ways until it is lifted', () async {
    await deliver(bob, alice, 'hello');

    expect(await blocked.block('user-bob', handle: 'bob'), isTrue);
    expect(blocked.isBlocked('user-bob'), isTrue);
    expect(relay.blockedEitherWay('user-alice', 'user-bob'), isTrue);

    // Bob's next message is refused by the relay and stays with him, failed.
    final stored = relay.conversations[conv]!.messages.length;
    await bob.controller.sendText(conversationId: conv, body: 'are you there?');
    await settle();
    final refused = bob.controller.messagesFor(conv).last;
    expect(refused.deliveryState, MessageDeliveryState.failed);
    expect(relay.conversations[conv]!.messages, hasLength(stored), reason: 'the relay took a send across a block');
    // Nor can Alice send to the account she blocked.
    await alice.controller.sendText(conversationId: conv, body: 'from the blocker');
    await settle();
    expect(alice.controller.messagesFor(conv).last.deliveryState, MessageDeliveryState.failed);
    expect(relay.conversations[conv]!.messages, hasLength(stored));

    expect(await blocked.unblock('user-bob'), isTrue);
    expect(blocked.isBlocked('user-bob'), isFalse);
    expect(relay.blockedEitherWay('user-alice', 'user-bob'), isFalse);

    // Bob's retry goes through now, and Alice reads it.
    final clientMessageId = refused.clientMessageId!;
    await bob.controller.retryPendingMessages(conv);
    await waitFor(() => bob.controller.pendingCountFor(conv) == 0, reason: 'the retry was not acked');
    expect(ownMessage(bob, clientMessageId).deliveryState, isNot(MessageDeliveryState.failed));
    await waitFor(() async => (await alice.bodies(conv)).contains('are you there?'), reason: 'the retry did not arrive');
    // And so does Alice's.
    await alice.controller.retryPendingMessages(conv);
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'the blocker\'s retry was not acked');
    await waitFor(() async => (await bob.bodies(conv)).contains('from the blocker'));
    await deliver(alice, bob, 'sorry, I am here');
  });

  test('the blocked list is read from the server, newest first', () async {
    relay.addParty(RelayParty(
      handle: 'carol',
      userId: 'user-carol',
      deviceId: 'dev-carol',
      identity: bob.device.identity,
    ));
    expect(await blocked.block('user-carol', handle: 'carol'), isTrue);
    expect(await blocked.block('user-bob', handle: 'bob'), isTrue);

    final fresh = BlockedAccounts(api: alice.api, accessToken: () => 'token-alice');
    addTearDown(fresh.dispose);
    await fresh.refresh();
    expect(fresh.loaded, isTrue);
    expect([for (final account in fresh.accounts) account.handle], ['bob', 'carol']);
    expect(fresh.byHandle('carol')?.userId, 'user-carol');
  });

  test('a muted chat raises no notification until the mute ends', () async {
    await deliver(bob, alice, 'first');
    expect(alice.notifications.shownForConversations, [conv]);

    expect(await mutes.mute(conv, MuteDuration.oneHour), isTrue);
    expect(relay.mutes['user-alice'], {conv: 3600}, reason: 'the server is told, for its pushes');
    expect(mutes.isMuted(conv), isTrue);
    await deliver(bob, alice, 'while muted');
    await settle();
    expect(alice.notifications.shownForConversations, [conv], reason: 'a muted chat notified');

    now = now.add(const Duration(hours: 1, seconds: 1));
    expect(mutes.isMuted(conv), isFalse);
    await deliver(bob, alice, 'after the mute');
    await settle();
    expect(alice.notifications.shownForConversations, [conv, conv]);
  });

  test('unmuting turns notifications back on at once', () async {
    expect(await mutes.mute(conv, MuteDuration.always), isTrue);
    expect(relay.mutes['user-alice'], {conv: null}, reason: 'a mute with no end');
    await deliver(bob, alice, 'muted');
    await settle();
    expect(alice.notifications.shownForConversations, isEmpty);

    expect(await mutes.unmute(conv), isTrue);
    expect(relay.mutes['user-alice'], isEmpty);
    await deliver(bob, alice, 'unmuted');
    await settle();
    expect(alice.notifications.shownForConversations, [conv]);
  });

  test('a message the relay took before a block arrives without a notification', () async {
    await deliver(bob, alice, 'hello');
    alice.notifications.shownForConversations.clear();
    // Sent while Alice's socket was down, so its event is still to come.
    alice.realtime.disconnect();
    await bob.controller.sendText(conversationId: conv, body: 'sent before the block');
    await waitFor(() => bob.controller.pendingCountFor(conv) == 0);
    final queued = Map<String, dynamic>.of(relay.conversations[conv]!.messages.last);

    expect(await blocked.block('user-bob', handle: 'bob'), isTrue);
    await alice.controller.handleAppResumed();
    await waitFor(() => alice.realtime.isConnected);
    alice.realtime.deliver('message.new', queued);
    await waitFor(() async => (await alice.bodies(conv)).contains('sent before the block'));
    await settle();
    expect(alice.notifications.shownForConversations, isEmpty);
  });

  test('a report carries the account, the reason and where it was filed from, nothing else', () async {
    await deliver(bob, alice, 'buy followers at cheap.example');
    final message = alice.controller.messagesFor(conv).firstWhere((each) => !each.isMine);
    final reports = AbuseReports(api: alice.api, accessToken: () => 'token-alice');

    expect(
      await reports.file(
        ReportTarget(userId: 'user-bob', handle: 'bob', conversationId: conv, messageId: message.id),
        ReportReason.spam,
      ),
      isTrue,
    );
    expect(await reports.file(const ReportTarget(userId: 'user-bob', handle: 'bob'), ReportReason.scam), isTrue);

    expect(relay.reports.map((report) => report.reporterUserId), ['user-alice', 'user-alice']);
    expect(relay.reports.first.fields, {
      'reportedUserId': 'user-bob',
      'reason': 'spam',
      'conversationId': conv,
      'messageId': message.id,
    });
    expect(relay.reports.last.fields, {'reportedUserId': 'user-bob', 'reason': 'scam'});
  });

  test('the reasons are the ones the server takes', () {
    expect(ReportReason.values.map((reason) => reason.wire),
        ['spam', 'harassment', 'impersonation', 'csam', 'violence', 'scam', 'other']);
  });

  group('mutes on this device', () {
    test('are kept with their end, and an ended one is dropped when read back', () async {
      final store = InMemoryIdentityKeyValueBackend();
      final first = ConversationMutes(store: store, api: alice.api, accessToken: () => 'token-alice', clock: () => now);
      addTearDown(first.dispose);
      expect(await first.mute(conv, MuteDuration.eightHours), isTrue);
      expect(first.mutedUntil(conv), now.add(const Duration(hours: 8)));

      final relaunched =
          ConversationMutes(store: store, api: alice.api, accessToken: () => 'token-alice', clock: () => now);
      addTearDown(relaunched.dispose);
      await relaunched.load();
      expect(relaunched.isMuted(conv), isTrue);

      now = now.add(const Duration(hours: 9));
      final later = ConversationMutes(store: store, api: alice.api, accessToken: () => 'token-alice', clock: () => now);
      addTearDown(later.dispose);
      await later.load();
      expect(later.isMuted(conv), isFalse);
      expect(await MuteStore(store).read(), isEmpty, reason: 'the ended mute was not dropped');
    });

    test('change nothing when the server refuses', () async {
      final strangers = ConversationMutes(
        store: InMemoryIdentityKeyValueBackend(),
        api: alice.api,
        accessToken: () => 'token-alice',
        clock: () => now,
      );
      addTearDown(strangers.dispose);
      // Alice is no member of this conversation.
      relay.addDirect('conv-other', 'bob', 'bob');
      expect(await strangers.mute('conv-other', MuteDuration.oneWeek), isFalse);
      expect(strangers.isMuted('conv-other'), isFalse);
      expect(relay.mutes['user-alice'], isNull);
    });
  });
}
