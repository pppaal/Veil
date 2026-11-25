import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/conversations/presentation/peer_names.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/features/safety/data/blocked_accounts.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';

import '../../support/fake_relay.dart';
import 'layout_seed.dart';
import 'layout_world.dart';

// What the trust layer knows in the layout world, and the chats of the
// trust cases. Every chat of the seeded morning was on the phone before
// this phone kept trust records (the baseline), and every nickname alex
// gave is that old too: the old cases show no request and no trust banner.
// The trust cases add a stranger's chat on top: a 1:1 request, a group
// request, a look-alike of Sam's handle, a new account that says it is
// family, or Sam's own chat with his number never compared (the nudge).

/// Which trust state a chat of the cases is in (ChatAttention.trust).
enum TrustCase {
  /// noah_park, whom alex never talked to, wrote first: a 1:1 request.
  request,

  /// noah_park added alex to a group with ines.v: a group request.
  groupRequest,

  /// sam.official, which imitates Sam's verified handle, wrote, and alex
  /// accepted the chat.
  lookalike,

  /// jess.kim, a new account, wrote "Hi mum, this is my new number", and
  /// alex accepted the chat.
  claim,

  /// Sam's own chat, his safety number never compared: the verify nudge.
  nudge,
}

/// The stranger of the request cases and the group request.
const strangerHandle = 'noah_park';
const strangerConversationId = 'conv-$strangerHandle';
const strangerLines = ["Hi Alex, it's Noah from the climbing gym", 'are you still selling the bike?'];

/// The group a stranger added alex to, with one more stranger.
const strangerGroupId = 'conv-run-club';
const strangerGroupName = 'Saturday run club';
const strangerGroupMember = 'ines.v';
const strangerGroupLines = ['Welcome! We meet at 8 by the lake', 'bring water, it gets hot'];

/// The account whose handle reads as Sam's.
const lookalikeHandle = 'sam.official';
const lookalikeConversationId = 'conv-$lookalikeHandle';
const lookalikeLines = ["hey, it's Sam", 'is the lease signed?'];

/// The new account that says it is family.
const claimHandle = 'jess.kim';
const claimConversationId = 'conv-$claimHandle';
const claimLines = ['Hi mum, this is my new number', 'my old phone fell in the river'];

/// The chat each case opens.
String trustChatOf(TrustCase trustCase) => switch (trustCase) {
      TrustCase.request => strangerConversationId,
      TrustCase.groupRequest => strangerGroupId,
      TrustCase.lookalike => lookalikeConversationId,
      TrustCase.claim => claimConversationId,
      TrustCase.nudge => chatConversationId,
    };

/// A party the relay knows, as user-[handle] on dev-[handle].
RelayParty trustParty(FakeRelay relay, LayoutIdentities identities, String handle) {
  final existing = relay.partiesByHandle[handle];
  if (existing != null) return existing;
  final party = RelayParty(handle: handle, userId: 'user-$handle', deviceId: 'dev-$handle', identity: identities.peer);
  relay.addParty(party);
  return party;
}

/// Seals [lines] from [from] into [conversationId] as the relay stores
/// them, one minute apart from [firstAt], before this phone lists anything.
Future<void> sealLines(
  FakeRelay relay,
  String conversationId,
  String from,
  List<String> lines, {
  required DateTime firstAt,
}) async {
  final sealer = createDefaultCryptoAdapter();
  for (final (index, body) in lines.indexed) {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$from',
      recipientUserId: 'user-$selfHandle',
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-$selfHandle',
        deviceId: 'dev-$selfHandle',
        handle: selfHandle,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final stored = relay.inject(
      senderHandle: from,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    stored['serverReceivedAt'] = firstAt.add(Duration(minutes: index)).toIso8601String();
  }
}

/// Adds the chat of [trustCase] to the relay, before the first list.
Future<void> seedTrustChat(FakeRelay relay, LayoutIdentities identities, TrustCase trustCase) async {
  final at = DateTime.utc(2026, 4, 7, 10, 5);
  switch (trustCase) {
    case TrustCase.request:
      trustParty(relay, identities, strangerHandle);
      relay.addDirect(strangerConversationId, selfHandle, strangerHandle);
      await sealLines(relay, strangerConversationId, strangerHandle, strangerLines, firstAt: at);
    case TrustCase.groupRequest:
      trustParty(relay, identities, strangerHandle);
      trustParty(relay, identities, strangerGroupMember);
      relay.addGroup(strangerGroupId, [strangerHandle, selfHandle, strangerGroupMember],
          useSenderKeys: false, name: strangerGroupName);
      await sealLines(relay, strangerGroupId, strangerHandle, strangerGroupLines, firstAt: at);
    case TrustCase.lookalike:
      trustParty(relay, identities, lookalikeHandle);
      relay.addDirect(lookalikeConversationId, selfHandle, lookalikeHandle);
      await sealLines(relay, lookalikeConversationId, lookalikeHandle, lookalikeLines, firstAt: at);
    case TrustCase.claim:
      trustParty(relay, identities, claimHandle);
      relay.addDirect(claimConversationId, selfHandle, claimHandle);
      await sealLines(relay, claimConversationId, claimHandle, claimLines, firstAt: at);
    case TrustCase.nudge:
      break;
  }
}

/// The parties of [trustCase] whose group frames this phone must open:
/// their devices are pinned, as every group member's is.
Future<void> pinTrustParties(IdentityTrust trust, FakeRelay relay, TrustCase trustCase) async {
  if (trustCase != TrustCase.groupRequest) return;
  for (final handle in [strangerHandle, strangerGroupMember]) {
    await pinParty(trust, relay.partiesByHandle[handle]!);
  }
}

/// Pins [party]'s device, as the first frame from it does.
Future<void> pinParty(IdentityTrust trust, RelayParty party) =>
    trust.resolver.evaluate(party.userId, party.deviceId, party.identity.identityPublicKey);

/// Writes the trust document the cases start from: the baseline has run;
/// every chat alex has on the relay now is accepted from before it, apart
/// from [requests]; [acceptedAt] chats were accepted at that time instead
/// (by Accept, after the baseline); and every handle in [peerNames] with a
/// nickname had it before the baseline.
Future<void> writeTrustDocument(
  SecureStorageService storage,
  FakeRelay relay, {
  Set<String> requests = const {},
  Map<String, DateTime> acceptedAt = const {},
}) async {
  final chats = <String, dynamic>{};
  for (final conversation in relay.conversations.values) {
    if (!conversation.memberHandles.contains(selfHandle) || requests.contains(conversation.id)) continue;
    final accepted = acceptedAt[conversation.id]?.millisecondsSinceEpoch;
    final mine = conversation.messages.any((message) => message['senderDeviceId'] == 'dev-$selfHandle');
    chats[conversation.id] = accepted == null
        ? {'seen': 0, 'accepted': 0, 'sent': null, if (mine) 'mine0': true, 'gone': null}
        : {'seen': accepted - const Duration(minutes: 30).inMilliseconds, 'accepted': accepted, 'sent': null, 'gone': null};
  }
  final document = ContactTrustDocument.fromJson({
    'v': 1,
    'baseline': true,
    'chats': chats,
    'named': {
      for (final MapEntry(key: handle, value: name) in peerNames.entries)
        if (name != null) handle: 0,
    },
  });
  await ContactTrustStore(storage.scoped(SecureScope.conversationPolicy)).write(document);
}

/// What the trust document of [trustCase] leaves as requests, and when it
/// accepted the chats accepted after the baseline.
({Set<String> requests, Map<String, DateTime> acceptedAt}) trustDocumentOf(TrustCase? trustCase) {
  final accepted = layoutNow.subtract(const Duration(minutes: 10));
  return switch (trustCase) {
    TrustCase.request => (requests: {strangerConversationId}, acceptedAt: const {}),
    TrustCase.groupRequest => (requests: {strangerGroupId}, acceptedAt: const {}),
    TrustCase.lookalike => (requests: const {}, acceptedAt: {lookalikeConversationId: accepted}),
    TrustCase.claim => (requests: const {}, acceptedAt: {claimConversationId: accepted}),
    TrustCase.nudge || null => (requests: const {}, acceptedAt: const {}),
  };
}

/// Attaches [trust] to [messenger] as messengerControllerProvider does in
/// the app: names from the nicknames alex gave ([book]), [blocked] once a
/// screen has read it.
void attachLayoutTrust(
  ContactTrust trust,
  VeilMessengerController messenger, {
  required IdentityTrust identityTrust,
  required ContactNameBook book,
  required BlockedAccounts? Function() blocked,
}) {
  trust.attach(
    messenger,
    trustEvents: identityTrust.events,
    savedName: (userId, handle) =>
        peerNamesFor(messenger, book.nicknames, blocked: blocked()?.accounts ?? const []).accountName(userId, handle),
    nicknames: () => {
      for (final MapEntry(:key, :value) in book.nicknames.entries) key: (name: value.name, userId: value.userId),
    },
    nicknamesChanged: book,
  );
}

/// [handle] writes [lines] to alex after the first list: in a 1:1, or with
/// [groupWith] in a group of alex, [handle] and those members, named
/// [groupName]. This phone has no record of the chat, so it is a request.
/// Returns the chat's id.
Future<String> strangerWrites(
  LayoutWorld world,
  String handle,
  List<String> lines, {
  String? conversationId,
  List<String>? groupWith,
  String groupName = strangerGroupName,
}) async {
  final party = trustParty(world.relay, world.identities, handle);
  final String id;
  if (groupWith == null) {
    id = conversationId ?? 'conv-$handle';
    world.relay.addDirect(id, selfHandle, handle);
  } else {
    id = conversationId ?? 'conv-group-$handle';
    await pinParty(world.trust, party);
    for (final member in groupWith) {
      await pinParty(world.trust, trustParty(world.relay, world.identities, member));
    }
    world.relay.addGroup(id, [handle, selfHandle, ...groupWith], useSenderKeys: false, name: groupName);
  }
  await sealLines(world.relay, id, handle, lines, firstAt: layoutNow.subtract(const Duration(minutes: 10)));
  await world.messenger.refreshConversations();
  await world.messenger.loadConversationMessages(id);
  return id;
}

/// The trust document as [world]'s keystore holds it now.
Future<ContactTrustDocument> storedDocument(LayoutWorld world) async =>
    (await ContactTrustStore(world.storage.scoped(SecureScope.conversationPolicy)).read())!;
