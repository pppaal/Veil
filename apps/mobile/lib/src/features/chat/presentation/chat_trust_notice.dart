import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/safety/handle_lookalike.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/local_notice.dart';
import '../../conversations/presentation/peer_names.dart';
import '../../safety/application/contact_trust.dart';
import '../../safety/application/relationship.dart';
import '../../safety/data/safety_providers.dart';
import '../application/message_safety.dart';

/// Which trust banner a chat shows under its identity notices.
enum ChatTrustNoticeKind {
  /// The peer's handle imitates a saved or verified account's.
  lookalike,

  /// A new (or changed) account says it is family or someone with a new
  /// phone.
  claim,

  /// A saved contact the user talks to a lot and never verified.
  nudge,
}

/// The one trust banner of a chat (ChatStatusBanners draws it).
class ChatTrustNotice {
  const ChatTrustNotice.lookalike({required String this.name, required String this.handle})
      : kind = ChatTrustNoticeKind.lookalike,
        withAction = false;

  const ChatTrustNotice.claim({this.withAction = true})
      : kind = ChatTrustNoticeKind.claim,
        name = null,
        handle = null;

  const ChatTrustNotice.nudge({required String this.name})
      : kind = ChatTrustNoticeKind.nudge,
        handle = null,
        withAction = true;

  final ChatTrustNoticeKind kind;

  /// The look-alike's: the anchor's nickname, or its handle with its "@".
  /// The nudge's: what the chat calls the peer.
  final String? name;

  /// The look-alike's own handle, without its "@".
  final String? handle;

  /// Whether the banner carries Verify, which opens the safety number page.
  final bool withAction;

  /// A warning, under which the request bar's Accept is a plain button.
  bool get warns => kind != ChatTrustNoticeKind.nudge;

  @override
  bool operator ==(Object other) =>
      other is ChatTrustNotice &&
      other.kind == kind &&
      other.name == name &&
      other.handle == handle &&
      other.withAction == withAction;

  @override
  int get hashCode => Object.hash(kind, name, handle, withAction);
}

/// At most one trust banner: a look-alike, else a claim, else the nudge.
/// With [otherNotices] (an identity notice is up, which has an action of
/// its own) the claim shows without its action and the nudge not at all,
/// so a chat never has two banner actions.
ChatTrustNotice? pickTrustNotice({
  ChatTrustNotice? lookalike,
  bool claim = false,
  ChatTrustNotice? nudge,
  required bool otherNotices,
}) {
  if (lookalike != null) return lookalike;
  if (claim) return ChatTrustNotice.claim(withAction: !otherNotices);
  if (nudge != null && !otherNotices) return nudge;
  return null;
}

/// The one other party of a 1:1, or of a group with exactly one other
/// member; null for any other chat.
({String userId, String handle})? trustPeerOf(ConversationPreview chat, {String? localUserId}) {
  if (chat.type == ConversationType.direct) {
    final userId = chat.recipientBundle.userId;
    return userId.isEmpty || chat.peerHandle.isEmpty ? null : (userId: userId, handle: chat.peerHandle);
  }
  final others = [
    for (final member in chat.members)
      if (member.userId != localUserId) member,
  ];
  return others.length == 1 ? (userId: others.single.userId, handle: others.single.handle) : null;
}

/// In a group that has grown past two, the member who was the one other
/// party before it grew: the one other member no member-added notice in
/// [messages] names (memberChangeNotice). Null when none or more than one
/// is left, so a banner about that member ends when they leave.
({String userId, String handle})? keptTrustPeerOf(
  ConversationPreview chat,
  List<ChatMessage> messages, {
  String? localUserId,
}) {
  final joined = _joinedLater(chat, messages);
  if (joined.isEmpty) return null;
  final first = [
    for (final member in chat.members)
      if (member.userId != localUserId && !joined.contains(member.userId)) member,
  ];
  return first.length == 1 ? (userId: first.single.userId, handle: first.single.handle) : null;
}

// The members a group's member-added notices in [messages] name.
Set<String> _joinedLater(ConversationPreview chat, List<ChatMessage> messages) {
  if (chat.type != ConversationType.group) return const {};
  final added = '$localNoticeIdPrefix${LocalNoticeCodes.groupMemberAdded}:${chat.id}:';
  return {
    for (final message in messages)
      if (message.isLocalNotice && message.id.startsWith(added)) message.id.substring(added.length).split(':').first,
  };
}

/// A chat's trust banner (spec A9-A13): the look-alike warning, the claim
/// banner and the verify nudge, each decided on the phone. The claim reads
/// the risk lines of the chat (MessageSafety.claims), so a banner and a
/// line never disagree and a text is read once for both; once shown it is
/// recorded and stays until the peer is verified. The look-alike warning
/// is for a peer who is new or changed, now or when they first wrote here,
/// never for a contact saved or known before they wrote. When a two-person
/// group grows, a recorded claim and the look-alike warning stay about its
/// first other member (keptTrustPeerOf) until they are verified or leave.
mixin ChatTrustNotices<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  String get conversationId;

  // Whether this opening of the chat already counted the nudge for its peer.
  bool _nudgeCounted = false;
  // The member the last banner was about, for its Verify.
  ({String userId, String handle})? _bannerPeer;

  /// Forgets what this opening decided; called when the chat changes.
  void resetTrustNotices() {
    _nudgeCounted = false;
    _bannerPeer = null;
  }

  /// The trust banner [chat] shows now, given [messages] (its loaded
  /// history) and whether an identity notice is up ([otherNotices]). Called
  /// while the chat builds: it watches the trust layer and the names.
  ChatTrustNotice? trustNoticeFor(ConversationPreview? chat, List<ChatMessage> messages, {required bool otherNotices}) {
    final trust = ref.watch(contactTrustProvider);
    final names = ref.watch(peerNamesProvider);
    if (chat == null) return null;
    final localUserId = ref.read(messengerControllerProvider).localUserId;
    final ChatTrustNotice? notice;
    if (trustPeerOf(chat, localUserId: localUserId) case final peer?) {
      final claims = ref.watch(messageSafetyProvider(chat.id)).claims;
      _bannerPeer = peer;
      notice = pickTrustNotice(
        lookalike: _lookalike(trust, chat, peer, names, messages),
        claim:
            _claims(trust, chat, peer, claims: claims, joinedLater: _joinedLater(chat, messages).contains(peer.userId)),
        nudge: _nudge(trust, chat, peer, names, messages),
        otherNotices: otherNotices,
      );
    } else if (keptTrustPeerOf(chat, messages, localUserId: localUserId) case final peer?) {
      // A grown group: only what was there before it grew stays, about the
      // member it was about.
      _bannerPeer = peer;
      final pair = chat.copyWith(members: [
        for (final member in chat.members)
          if (member.userId == localUserId || member.userId == peer.userId) member,
      ]);
      final recorded =
          trust.ready && !trust.degraded && trust.claimHolds(chat.id) && !trust.verified.isVerified(peer.userId);
      notice = pickTrustNotice(
        lookalike: _lookalike(trust, pair, peer, names, messages),
        claim: recorded,
        otherNotices: otherNotices,
      );
    } else {
      _bannerPeer = null;
      return null;
    }
    final peer = _bannerPeer!;
    if (notice?.kind == ChatTrustNoticeKind.nudge && !_nudgeCounted) {
      _nudgeCounted = true;
      scheduleMicrotask(() => unawaited(trust.nudgeShown(peer.userId)));
    }
    // A claim is recorded once it is on screen (A11), not while a
    // look-alike warning stands in its place.
    if (notice?.kind == ChatTrustNoticeKind.claim && !trust.claimHolds(chat.id)) {
      scheduleMicrotask(() => unawaited(trust.noteClaim(chat.id)));
    }
    return notice;
  }

  /// Opens the safety number page for [chat]'s peer from a banner's
  /// Verify, then [then]; a nudge verified there never shows again.
  Future<void> verifyFromTrustNotice(ConversationPreview? chat, {required Future<void> Function() then}) async {
    final localUserId = ref.read(messengerControllerProvider).localUserId;
    final peer = chat == null ? null : trustPeerOf(chat, localUserId: localUserId) ?? _bannerPeer;
    if (chat == null || peer == null) return;
    // A group's page is about the one member the banner is about.
    final page = Uri(
      path: '/safety-numbers/${chat.id}',
      queryParameters: chat.type == ConversationType.group ? {'member': peer.userId} : null,
    );
    await context.push(page.toString());
    if (!mounted) return;
    await then();
    final trust = ref.read(contactTrustProvider);
    if (trust.verified.isVerified(peer.userId)) await trust.nudgeDone(peer.userId);
  }

  // Only a peer who is new or changed, now or when their first message
  // here was sent: two contacts saved long ago under one nickname, or a
  // parent's handle beside the child's, are no impostors, while a stranger
  // who got saved later still is.
  ChatTrustNotice? _lookalike(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer,
    PeerNames names,
    List<ChatMessage> messages,
  ) {
    final verified = trust.verified.isVerified(peer.userId);
    if (verified) return null;
    bool fresh(DateTime at) => switch (trust.relationshipAt(peer.userId, peer.handle, chat: chat, at: at)) {
          Relationship.newContact || Relationship.changed => true,
          _ => false,
        };
    final first = messages.where((message) => !message.isMine && !message.isLocalNotice).firstOrNull;
    if (!fresh(ref.read(wallClockProvider)()) && (first == null || !fresh(first.sentAt))) return null;
    final match = findLookalike(
      peer.handle,
      names.accountName(peer.userId, peer.handle),
      trust.anchorsFor(chat),
      peerUserId: peer.userId,
      peerVerified: verified,
    );
    if (match == null) return null;
    return ChatTrustNotice.lookalike(name: match.anchor.name ?? '@${match.anchor.handle}', handle: peer.handle);
  }

  // A claim recorded before holds until the peer is verified, or, in a
  // group, until the member it was about leaves: one who joined later
  // ([joinedLater]) is not who it was about. Otherwise a new account the
  // user did not start the chat with, or a changed one, shows it for a
  // family handle or for any of its texts the checker reads as a family or
  // new-phone claim at warn or higher ([claims]).
  bool _claims(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer, {
    required bool claims,
    required bool joinedLater,
  }) {
    if (!trust.ready || trust.degraded || trust.verified.isVerified(peer.userId)) return false;
    if (trust.claimHolds(chat.id) && !joinedLater) return true;
    final now = ref.read(wallClockProvider)();
    final relationship = trust.relationshipAt(peer.userId, peer.handle, chat: chat, at: now);
    final open = relationship == Relationship.changed ||
        (relationship == Relationship.newContact && !trust.startedByMe(chat.id));
    return open && (claims || isKinHandle(peer.handle));
  }

  // A 1:1 with a saved, unverified peer whose loaded history holds 20
  // messages or more, 5 of them mine: on at most three chat openings, and
  // through the whole of an opening that counted.
  ChatTrustNotice? _nudge(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer,
    PeerNames names,
    List<ChatMessage> messages,
  ) {
    if (chat.type != ConversationType.direct || trust.degraded || !trust.ready) return null;
    if (!_nudgeCounted && !trust.nudgeAllowed(peer.userId)) return null;
    final now = ref.read(wallClockProvider)();
    if (trust.relationshipAt(peer.userId, peer.handle, chat: chat, at: now) != Relationship.saved) return null;
    final shown = [for (final message in messages) if (!message.isLocalNotice) message];
    if (shown.length < 20 || shown.where((message) => message.isMine).length < 5) return null;
    return ChatTrustNotice.nudge(name: names.peerName(chat) ?? '@${peer.handle}');
  }
}
