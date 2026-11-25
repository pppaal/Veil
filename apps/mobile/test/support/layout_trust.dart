import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';

import '../layout/support/layout_world.dart';
import 'fake_relay.dart';

// Message requests, risk lines and link sheets on the layout world, which
// builds its own messenger: the trust layer attached to it as the app's
// messenger provider attaches it, and strangers who write first.

/// Attaches [world]'s trust layer to its messenger and waits for the
/// baseline, which accepts every chat of the first list (the seeded ones).
/// Call from withPhoneApp's afterSession, once that list is in. A trust
/// layer the world already attached and read is left as it is.
Future<ContactTrust> attachContactTrust(LayoutWorld world) async {
  final trust = world.container.read(unattachedContactTrustProvider);
  if (!trust.ready && !trust.degraded) trust.attach(world.messenger, trustEvents: world.trust.events);
  for (var i = 0; i < 200 && !trust.ready; i++) {
    await Future<void>.value();
  }
  expect(trust.ready, isTrue, reason: 'the trust document was not read, or the baseline did not run');
  return trust;
}

/// Adds [handle] to the relay as an account alex has never talked to
/// (call from beforeSession).
void addStranger(FakeRelay relay, LayoutIdentities identities, String handle) => relay.addParty(RelayParty(
      handle: handle,
      userId: 'user-$handle',
      deviceId: 'dev-$handle',
      identity: identities.peer,
    ));

/// [handle] opens a 1:1 with alex and writes [texts] in it, oldest first,
/// a minute apart up to the world's clock, so the chat is the newest in
/// Chats; [kind] each (a file's text is its name, with [attachment]).
/// Alex's messenger lists the chat and loads it. Returns the chat's id.
Future<String> strangerWrites(
  LayoutWorld world,
  String handle,
  List<String> texts, {
  MessageKind kind = MessageKind.text,
  AttachmentReference? attachment,
}) async {
  final conversationId = 'conv-$handle';
  if (!world.relay.conversations.containsKey(conversationId)) {
    world.relay.addDirect(conversationId, selfHandle, handle);
  }
  final sealer = createDefaultCryptoAdapter();
  for (final (index, text) in texts.indexed) {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$handle',
      recipientUserId: 'user-$selfHandle',
      body: text,
      messageKind: kind,
      attachment: attachment,
      recipientBundle: const KeyBundle(
        userId: 'user-$selfHandle',
        deviceId: 'dev-$selfHandle',
        handle: selfHandle,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final stored = world.relay.inject(
      senderHandle: handle,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    stored['serverReceivedAt'] = world.now.subtract(Duration(minutes: texts.length - index)).toIso8601String();
  }
  await world.messenger.refreshConversations();
  await world.messenger.loadConversationMessages(conversationId);
  return conversationId;
}
