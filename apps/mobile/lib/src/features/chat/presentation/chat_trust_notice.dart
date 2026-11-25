import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/safety/handle_lookalike.dart';
import '../../../core/safety/message_risk.dart';
import '../../../core/safety/rule_risk_checker.dart';
import '../../../core/safety/thread_risk.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/peer_names.dart';
import '../../safety/application/contact_trust.dart';
import '../../safety/application/relationship.dart';
import '../../safety/application/risk_relationship.dart';
import '../../safety/data/safety_providers.dart';

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

/// A chat's trust banner (spec A9-A13): the look-alike warning, the claim
/// banner and the verify nudge, each decided on the phone. The claim reads
/// the peer's last texts with the same checker the risk lines use
/// (assessThread), so a banner and a line never disagree; once shown it is
/// recorded and stays until the peer is verified.
mixin ChatTrustNotices<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  String get conversationId;

  // The texts the claim check last read (their ids), and what it found.
  String? _claimRead;
  bool _claimFound = false;
  // Whether this opening of the chat already counted the nudge for its peer.
  bool _nudgeCounted = false;

  /// Forgets what this opening decided; called when the chat changes.
  void resetTrustNotices() {
    _claimRead = null;
    _claimFound = false;
    _nudgeCounted = false;
  }

  /// The trust banner [chat] shows now, given [messages] (its loaded
  /// history) and whether an identity notice is up ([otherNotices]). Called
  /// while the chat builds: it watches the trust layer and the names.
  ChatTrustNotice? trustNoticeFor(ConversationPreview? chat, List<ChatMessage> messages, {required bool otherNotices}) {
    final trust = ref.watch(contactTrustProvider);
    final names = ref.watch(peerNamesProvider);
    if (chat == null) return null;
    final peer = trustPeerOf(chat, localUserId: ref.read(messengerControllerProvider).localUserId);
    if (peer == null) return null;
    final notice = pickTrustNotice(
      lookalike: _lookalike(trust, chat, peer, names),
      claim: _claims(trust, chat, peer, messages),
      nudge: _nudge(trust, chat, peer, names, messages),
      otherNotices: otherNotices,
    );
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
    final peer = chat == null ? null : trustPeerOf(chat, localUserId: localUserId);
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

  ChatTrustNotice? _lookalike(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer,
    PeerNames names,
  ) {
    final verified = trust.verified.isVerified(peer.userId);
    if (verified) return null;
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

  // A claim recorded before holds until the peer is verified. Otherwise a
  // new account the user did not start the chat with, or a changed one,
  // shows it for a family handle or for any of its last texts the checker
  // reads as a family or new-phone claim at warn or higher.
  bool _claims(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer,
    List<ChatMessage> messages,
  ) {
    if (!trust.ready || trust.degraded || trust.verified.isVerified(peer.userId)) return false;
    if (trust.claimHolds(chat.id)) return true;
    final now = ref.read(wallClockProvider)();
    final relationship = trust.relationshipAt(peer.userId, peer.handle, chat: chat, at: now);
    final startedByMe = trust.startedByMe(chat.id);
    final open = relationship == Relationship.changed || (relationship == Relationship.newContact && !startedByMe);
    if (!open) return false;
    if (_claimFound || isKinHandle(peer.handle)) return true;
    unawaited(_readClaims(trust, chat, peer, messages, startedByMe: startedByMe));
    return false;
  }

  Future<void> _readClaims(
    ContactTrust trust,
    ConversationPreview chat,
    ({String userId, String handle}) peer,
    List<ChatMessage> messages, {
    required bool startedByMe,
  }) async {
    final theirs = [
      for (final message in messages)
        if (!message.isMine && !message.isLocalNotice && message.envelope.messageKind == MessageKind.text) message,
    ];
    final last = theirs.length > threadRiskTexts ? theirs.sublist(theirs.length - threadRiskTexts) : theirs;
    final read = '${chat.id}:${last.map((message) => message.id).join(',')}';
    if (read == _claimRead) return;
    _claimRead = read;
    final controller = ref.read(messengerControllerProvider);
    final texts = <({String text, DateTime at, RiskRelationship relationship})>[];
    for (final message in last) {
      final opened = await controller.decryptMessage(message);
      if (!mounted || _claimRead != read) return;
      if (!opened.isOk || opened.messageKind != MessageKind.text || opened.body.isEmpty) continue;
      final relationship = trust.relationshipAt(peer.userId, peer.handle, chat: chat, at: message.sentAt);
      texts.add((text: opened.body, at: message.sentAt, relationship: riskRelationshipOf(relationship)));
    }
    final claimed = assessThread(const RuleRiskChecker(), texts, startedByMe: startedByMe).any((risk) =>
        risk.level.index >= RiskLevel.warn.index &&
        (risk.reason == RiskReason.familyClaim || risk.reason == RiskReason.newPhoneClaim));
    if (!claimed || !mounted || _claimRead != read) return;
    setState(() => _claimFound = true);
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
