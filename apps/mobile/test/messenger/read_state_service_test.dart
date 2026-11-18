import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/conversation_read_mark.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/cache_handle.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

// What the read state does with real controllers over the fake relay: when
// the read mark moves, what it counts, the one read receipt each move sends
// (and the ones it never sends), the fresh-device baseline and the unread
// divider. Atlas reads; selene and rowan write to atlas.

const conv = 'conv-1';
const other = 'conv-2';

void main() {
  late FakeRelay relay;
  late IdentityTrust trust;
  late Set<String> blocked;
  late RecordingNotifications notifications;
  late bool receipts;
  late VeilMessengerController atlas;
  late VeilMessengerController selene;
  late VeilMessengerController rowan;
  final disposeLater = <VeilMessengerController>[];

  VeilMessengerController atlasOn(ConversationCacheService? cache) {
    final crypto = StrictMockCryptoAdapter(localDeviceId: 'dev-atlas');
    final controller = VeilMessengerController(
      apiClient: relay.clientFor('atlas'),
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: relay.realtimeFor('atlas'),
      cacheService: cache,
      notificationService: notifications,
      readReceiptsEnabled: () => receipts,
      identityTrust: trust,
      isBlockedDirect: blocked.contains,
    );
    disposeLater.add(controller);
    return controller;
  }

  Future<VeilMessengerController> peer(String handle) async {
    final controller = mockPartyController(relay, handle);
    disposeLater.add(controller);
    await controller.applySession(mockPartySession(handle));
    return controller;
  }

  setUp(() async {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    seedMockParties(relay, other, ['atlas', 'rowan']);
    trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
    blocked = {};
    notifications = RecordingNotifications();
    receipts = true;
    atlas = atlasOn(null);
    await atlas.applySession(mockPartySession('atlas'));
    selene = await peer('selene');
    rowan = await peer('rowan');
  });

  tearDown(() {
    for (final controller in disposeLater) {
      controller.dispose();
    }
    disposeLater.clear();
  });

  List<String> markReadCalls() => relay.clientFor('atlas').markReadCalls;
  int unread([String id = conv]) => atlas.reads.unreadCount(id);

  Future<void> say(VeilMessengerController from, String body, {String to = conv}) async {
    final before = atlas.messagesFor(to).length;
    await from.sendText(conversationId: to, body: body);
    await waitFor(() => atlas.messagesFor(to).length > before, reason: '"$body" did not reach atlas');
  }

  // Lets the advance run and its receipt be looked up and sent.
  Future<void> read(String id) async {
    atlas.setActiveConversation(id);
    await settle();
  }

  // A message on the relay that atlas has not fetched yet, sealed by the
  // mock engine (any mock instance opens it).
  final sealer = createDefaultCryptoAdapter();
  Future<void> inject(String from, String body, {String to = conv, MessageKind kind = MessageKind.text}) async {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: to,
      senderDeviceId: 'dev-$from',
      recipientUserId: 'user-atlas',
      body: body,
      messageKind: kind,
      recipientBundle: const KeyBundle(
        userId: 'user-atlas',
        deviceId: 'dev-atlas',
        handle: 'atlas',
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    relay.inject(senderHandle: from, conversationId: to, envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope));
  }

  String newestFromSelene() => atlas.messagesFor(conv).lastWhere((message) => !message.isMine).id;

  group('becoming active', () {
    test('moves the mark, counts 0, sends exactly one receipt for the newest message and cancels the notification',
        () async {
      for (final body in ['one', 'two', 'three']) {
        await say(selene, body);
      }
      expect(unread(), 3);
      expect(notifications.shownForConversations, [conv, conv, conv]);
      final newest = newestFromSelene();

      await read(conv);
      expect(unread(), 0);
      expect(markReadCalls(), [newest]);
      expect(atlas.reads.isUnread(conv), isFalse);
      expect(notifications.cancelledForConversations, contains(conv));
      final orders = atlas.messagesFor(conv).map((message) => message.conversationOrder!).toList();
      expect(atlas.reads.markedUnread(conv), isFalse);
      expect(atlas.messagesFor(conv).every((message) => message.conversationOrder! <= orders.last), isTrue);

      // Back again with nothing new: nothing more is sent.
      atlas.setActiveConversation(null);
      await read(conv);
      expect(markReadCalls(), [newest]);
    });

    test('sends no receipt with receipts off, and the mark still moves', () async {
      receipts = false;
      await say(selene, 'are you there?');
      expect(unread(), 1);
      await read(conv);
      expect(unread(), 0);
      expect(markReadCalls(), isEmpty);
    });

    test('a page of 50 synced into the open chat is one move and one receipt; into another chat it counts 50',
        () async {
      await read(conv);
      for (var index = 0; index < 50; index++) {
        await inject('selene', 'backlog $index');
      }
      await atlas.loadConversationMessages(conv);
      await settle();
      expect(atlas.messagesFor(conv), hasLength(50));
      expect(unread(), 0);
      expect(markReadCalls(), [newestFromSelene()]);

      for (var index = 0; index < 50; index++) {
        await inject('rowan', 'elsewhere $index', to: other);
      }
      await atlas.loadConversationMessages(other);
      await settle();
      expect(unread(other), 50);
      expect(markReadCalls(), hasLength(1));
    });

    test('an own message acked while the chat is not open moves nothing', () async {
      await say(selene, 'hello');
      await atlas.sendText(conversationId: conv, body: 'from atlas, sent from the list');
      await waitFor(() => atlas.pendingCountFor(conv) == 0);
      expect(atlas.reads.unreadCount(conv), 1);
      expect(atlas.reads.readMarkOf(conv), isNull);
    });
  });

  group('mark as read and unread', () {
    test('Mark as unread sets the flag only; opening then clears it and sends nothing', () async {
      await say(selene, 'look at this');
      await read(conv);
      expect(markReadCalls(), hasLength(1));
      atlas.setActiveConversation(null);
      final fetches = relay.clientFor('atlas').conversationFetches + relay.clientFor('atlas').messageFetches;

      atlas.reads.markUnread(conv);
      await settle();
      expect(atlas.reads.markedUnread(conv), isTrue);
      expect(atlas.reads.isUnread(conv), isTrue);
      expect(unread(), 0);
      expect(markReadCalls(), hasLength(1), reason: 'marking unread takes no receipt back and sends none');
      expect(relay.clientFor('atlas').conversationFetches + relay.clientFor('atlas').messageFetches, fetches);

      await read(conv);
      expect(atlas.reads.markedUnread(conv), isFalse);
      expect(markReadCalls(), hasLength(1));
    });

    test('Mark as read from the list sends one receipt with receipts on', () async {
      await say(selene, 'first');
      await say(selene, 'second');
      atlas.reads.markRead(conv);
      await settle();
      expect(unread(), 0);
      expect(markReadCalls(), [newestFromSelene()]);
    });

    test('Mark as read from the list sends none with receipts off', () async {
      receipts = false;
      await say(selene, 'first');
      atlas.reads.markRead(conv);
      await settle();
      expect(unread(), 0);
      expect(markReadCalls(), isEmpty);
    });

    test('Mark as read with nothing loaded reads through the list\'s last message and sends nothing', () async {
      await inject('selene', 'not fetched');
      await atlas.refreshConversations();
      final listed = atlas.conversationById(conv)!.lastMessageOrder;
      expect(listed, isNotNull);
      atlas.reads.markRead(conv);
      await settle();
      expect(atlas.reads.readMarkOf(conv)?.readThrough, listed);
      expect(markReadCalls(), isEmpty);
    });
  });

  test('switching receipts on later sends nothing for what was read while they were off', () async {
    receipts = false;
    await say(selene, 'while off');
    await read(conv);
    receipts = true;
    atlas.setActiveConversation(null);
    await read(conv);
    expect(markReadCalls(), isEmpty);

    // The next message read is receipted, and only it.
    await say(selene, 'now on');
    await waitFor(() => markReadCalls().length == 1);
    expect(markReadCalls(), [newestFromSelene()]);
  });

  test('an unread message that expires leaves the count, and its notification goes at 0', () async {
    await selene.sendText(conversationId: conv, body: 'gone soon', disappearAfter: const Duration(seconds: 2));
    await waitFor(() => unread() == 1);
    expect(notifications.cancelledForConversations, isEmpty);
    await waitFor(() => unread() == 0, timeout: const Duration(seconds: 8), reason: 'the expired message still counts');
    expect(notifications.cancelledForConversations, contains(conv));
  });

  test('a held chat counts; a screenshot line and a reaction do not', () async {
    await say(selene, 'counted');
    await selene.sendSystemNotice(conversationId: conv, body: '@selene took a screenshot');
    await waitFor(() => atlas.messagesFor(conv).length == 2);
    final text = atlas.messagesFor(conv).first;
    final seleneCopy = selene.messagesFor(conv).first;
    await selene.toggleReaction(seleneCopy, '\u{1F44D}');
    await waitFor(() => relay.conversations[conv]!.messages.length == 3);
    await atlas.loadConversationMessages(conv);
    expect(unread(), 1);
    expect(text.envelope.messageKind, MessageKind.text);

    // Who selene is now waits for atlas: the chat is held, and still counts.
    final party = relay.partiesByHandle['selene']!;
    await trust.resolver.evaluate(party.userId, party.deviceId, party.identity.identityPublicKey);
    await trust.admit(conv, party.userId, party.deviceId, base64UrlNoPadEncode(utf8.encode('ik-selene-new')));
    expect(atlas.pendingIdentityChangeFor(conv), isNotNull);
    await say(selene, 'while held');
    expect(unread(), 2);
  });

  group('the receipt goes for the newest message that opened and counts', () {
    test('not for a local notice at the end of the chat', () async {
      await say(selene, 'the real one');
      final real = newestFromSelene();
      // Selene turns on the timer: atlas writes the notice after her line.
      relay.realtimeFor('atlas').deliver('conversation.timer.changed', {
        'conversationId': conv,
        'disappearingTimerSeconds': 3600,
      });
      await waitFor(() => atlas.messagesFor(conv).last.isLocalNotice, reason: 'no timer notice was written');
      await read(conv);
      expect(markReadCalls(), [real]);
    });

    test('not for a reaction at the end of the chat', () async {
      await say(selene, 'react to me');
      final text = newestFromSelene();
      await selene.toggleReaction(selene.messagesFor(conv).single, '\u{2764}\u{FE0F}');
      await waitFor(() => atlas.messagesFor(conv).length == 2);
      await read(conv);
      expect(markReadCalls(), [text]);
    });

    test('not for a system line at the end of the chat', () async {
      await say(selene, 'before the screenshot');
      final text = newestFromSelene();
      await selene.sendSystemNotice(conversationId: conv, body: '@selene took a screenshot');
      await waitFor(() => atlas.messagesFor(conv).length == 2);
      await read(conv);
      expect(markReadCalls(), [text]);
    });

    test('not for a message whose content did not open', () async {
      await say(selene, 'this one opens');
      final text = newestFromSelene();
      relay.inject(
        senderHandle: 'selene',
        conversationId: conv,
        envelope: {
          'conversationId': conv,
          'senderDeviceId': 'dev-selene',
          'recipientUserId': 'user-atlas',
          'ciphertext': 'not-a-frame-this-engine-sealed',
          'nonce': 'n',
          'messageType': 'text',
          'version': sealer.envelopeCodec.defaultEnvelopeVersion,
        },
      );
      await atlas.loadConversationMessages(conv);
      expect(atlas.messagesFor(conv), hasLength(2));
      await read(conv);
      expect(markReadCalls(), [text]);
    });
  });

  group('receipts are withheld, and the mark still moves', () {
    Future<void> expectWithheld(String id, {required Future<void> Function() arrange}) async {
      await say(selene, 'one');
      await say(selene, 'two');
      await arrange();
      expect(atlas.reads.receiptsWithheld(id), isTrue);
      await read(id);
      expect(unread(id), 0);
      expect(markReadCalls(), isEmpty);
    }

    test('in a chat with an identity change pending', () async {
      await expectWithheld(conv, arrange: () async {
        final party = relay.partiesByHandle['selene']!;
        await trust.resolver.evaluate(party.userId, party.deviceId, party.identity.identityPublicKey);
        await trust.admit(conv, party.userId, party.deviceId, base64UrlNoPadEncode(utf8.encode('ik-selene-new')));
      });
    });

    test('in a 1:1 held for its account', () async {
      await expectWithheld(conv, arrange: () async {
        relay.listedHandles['atlas'] = {'selene': 'atlas'};
        await atlas.refreshConversations();
        expect(atlas.peerAccountHoldFor(conv), isNotNull);
      });
    });

    test('in a 1:1 whose peer has a change pending in a group', () async {
      relay.addGroup('conv-team', ['atlas', 'selene'], useSenderKeys: false);
      await atlas.refreshConversations();
      await expectWithheld(conv, arrange: () async {
        final party = relay.partiesByHandle['selene']!;
        await trust.resolver.evaluate(party.userId, party.deviceId, party.identity.identityPublicKey);
        await trust.admit('conv-team', party.userId, party.deviceId, base64UrlNoPadEncode(utf8.encode('ik-new')));
        expect(atlas.pendingIdentityChangeFor(conv), isNull);
      });
    });

    test('in a 1:1 whose peer is blocked', () async {
      await expectWithheld(conv, arrange: () async => blocked.add(conv));
    });

    test('and Mark as read on a held chat sends nothing either', () async {
      await say(selene, 'held');
      blocked.add(conv);
      atlas.reads.markRead(conv);
      await settle();
      expect(unread(), 0);
      expect(markReadCalls(), isEmpty);

      // Nothing read while withheld is receipted later.
      blocked.remove(conv);
      await read(conv);
      expect(markReadCalls(), isEmpty);
    });
  });

  group('the first list on a new device', () {
    // The encrypted cache over an in-memory database, which a fresh install
    // creates with the baseline marker; it records each write.
    late AppDatabase database;
    late _RecordingCache cache;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      cache = _RecordingCache(database, envelopeCodec: sealer.envelopeCodec);
    });

    tearDown(() => database.close());

    Future<VeilMessengerController> signInAtlas(ConversationCacheService? on) async {
      atlas.dispose();
      disposeLater.remove(atlas);
      final controller = atlasOn(on);
      await controller.applySession(mockPartySession('atlas'));
      return controller;
    }

    test('reads every listed conversation through its last message, and spends the marker in that write', () async {
      relay.addDirect('conv-3', 'atlas', 'rowan');
      await inject('selene', 'old one');
      await inject('rowan', 'old two', to: other);
      await inject('rowan', 'old three', to: 'conv-3');
      atlas = await signInAtlas(cache);
      await waitFor(() => [conv, other, 'conv-3'].every((id) => atlas.messagesFor(id).isNotEmpty),
          reason: 'the listed conversations were not loaded');
      await atlas.flushPendingWrites();

      for (final id in [conv, other, 'conv-3']) {
        expect(unread(id), 0, reason: id);
      }
      final spent = cache.writes.where((changes) => changes.consumeBaselineMarker).toList();
      expect(spent, hasLength(1));
      expect(spent.single.readMarks.keys.toSet(), {conv, other, 'conv-3'});
      final snapshot = await cache.readSnapshot();
      expect(snapshot.baselinePending, isFalse);
      expect(snapshot.readMarks[conv], const ConversationReadMark(readThrough: 1));
    });

    test('a new account\'s first chat that arrives while the app is closed counts after the restart', () async {
      relay.conversations.remove(conv);
      relay.conversations.remove(other);
      atlas = await signInAtlas(cache);
      await atlas.flushPendingWrites();
      expect((await cache.readSnapshot()).baselinePending, isFalse, reason: 'the empty first list spends it');

      atlas.dispose();
      disposeLater.remove(atlas);
      seedMockParties(relay, conv, ['atlas', 'selene']);
      await inject('selene', 'hi, is this you?');
      atlas = atlasOn(cache);
      await atlas.applySession(mockPartySession('atlas'));
      await waitFor(() => atlas.messagesFor(conv).isNotEmpty);
      expect(unread(), 1);
    });

    test('a cache that cannot be read is not baselined', () async {
      await inject('selene', 'waiting on the relay');
      atlas = await signInAtlas(CacheHandle(() async => throw StateError('before first unlock')));
      await waitFor(() => atlas.messagesFor(conv).isNotEmpty);
      expect(unread(), 1);
    });

    test('a chat listed later counts', () async {
      atlas = await signInAtlas(cache);
      relay.addDirect('conv-new', 'atlas', 'rowan');
      await inject('rowan', 'new chat', to: 'conv-new');
      await atlas.refreshConversations();
      await waitFor(() => atlas.messagesFor('conv-new').isNotEmpty);
      expect(unread('conv-new'), 1);
    });
  });

  group('the unread divider', () {
    test('says what was unread when the screen began, and keeps it while the chat comes and goes', () async {
      for (var index = 0; index < 4; index++) {
        await say(selene, 'line $index');
      }
      final viewer = Object();
      atlas.reads.beginViewing(conv, viewer: viewer);
      await read(conv);
      expect(unread(), 0);
      final divider = atlas.reads.dividerFor(conv, viewer: viewer)!;
      expect(divider.count, 4);
      expect(divider.olderThanLoaded, isFalse);
      expect(divider.firstMessageId, atlas.messagesFor(conv).first.id);

      // A sheet, the lock screen, background: the chat stops and starts
      // being active, and the divider stays.
      atlas.setActiveConversation(null);
      await say(selene, 'while away');
      await read(conv);
      expect(atlas.reads.dividerFor(conv, viewer: viewer)?.count, 4);

      // The same screen beginning again takes nothing new.
      atlas.reads.beginViewing(conv, viewer: viewer);
      expect(atlas.reads.dividerFor(conv, viewer: viewer)?.count, 4);

      atlas.reads.endViewing(conv, viewer: viewer);
      final next = Object();
      atlas.reads.beginViewing(conv, viewer: next);
      expect(atlas.reads.dividerFor(conv, viewer: next), isNull);
    });

    test('a chat marked unread with nothing counted has none', () async {
      await say(selene, 'read already');
      await read(conv);
      atlas.setActiveConversation(null);
      atlas.reads.markUnread(conv);
      final viewer = Object();
      atlas.reads.beginViewing(conv, viewer: viewer);
      expect(atlas.reads.dividerFor(conv, viewer: viewer), isNull);
    });
  });
}

class _RecordingCache extends DriftConversationCacheService {
  _RecordingCache(super.db, {required super.envelopeCodec});

  final List<ConversationCacheChanges> writes = [];

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) {
    writes.add(changes);
    return super.writeChanges(changes);
  }
}
