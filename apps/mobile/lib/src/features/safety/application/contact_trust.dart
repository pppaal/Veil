import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/identity_trust.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import '../data/contact_trust_store.dart';
import 'relationship.dart';
import 'verified_accounts.dart';

/// A nickname as ContactTrust reads it: the name, and the account it names
/// (null until PeerNames claims one).
typedef TrustNickname = ({String name, String? userId});

/// A saved or verified account a 1:1 peer's handle is compared with
/// (core/safety's LookalikeAnchor has the same shape).
typedef TrustAnchor = ({String userId, String handle, String? name, bool verified});

/// Who each account is to this phone and which chats are message requests,
/// decided on the phone from what it recorded itself (`contact_trust.v1`,
/// [ContactTrustStore]) and what the messenger, the pins and the nicknames
/// say. Nothing of it is sent anywhere.
///
/// A chat is a request until it is accepted, which is sticky: Accept; a 1:1
/// started from a typed handle ([startDirect]); the group [acceptCreated]
/// names; a text or file this phone sends in it ([noteOwnSend], called by
/// the messenger's sendText and sendAttachment, never for a system notice
/// or a reaction); its peer becoming verified; a 1:1 whose handle had a
/// nickname before the chat was first seen; a group whose every other
/// member is verified, saved or known; and the baseline: every chat in the
/// first relay list after install or upgrade. A nickname saved later does
/// not accept a chat. Records of chats that leave the list are kept (gone)
/// for 180 days, so one empty or lying list does not undo any accept.
///
/// Until the document is read, and while the baseline is pending, no chat
/// is a request but every chat [withholds] read receipts, typing and
/// automatic fetches. A read that fails is tried again on the next
/// messenger change after each of [retryDelays]; when the last fails, the
/// trust layer runs [degraded] until the next sign-in: no requests, nothing
/// withheld, nothing written.
class ContactTrust extends ChangeNotifier {
  ContactTrust({
    required ContactTrustStore store,
    required this.verified,
    DateTime Function()? clock,
    List<Duration> retryDelays = const [Duration(seconds: 1), Duration(seconds: 5), Duration(seconds: 30)],
    Duration writeDelay = const Duration(milliseconds: 300),
    void Function(String line)? log,
  })  : _store = store,
        _clock = clock ?? DateTime.now,
        _retryDelays = retryDelays,
        _writeDelay = writeDelay,
        _log = log ?? debugPrint;

  static const _week = Duration(days: 7);
  static const _keepGone = Duration(days: 180);

  final ContactTrustStore _store;
  final VerifiedAccounts verified;
  final DateTime Function() _clock;
  final List<Duration> _retryDelays;
  final Duration _writeDelay;
  final void Function(String line) _log;

  VeilMessengerController? _facade;
  String? Function(String userId, String handle) _savedName = (_, __) => null;
  Map<String, TrustNickname> Function() _nicknames = () => const {};
  Listenable? _nicknamesChanged;
  StreamSubscription<IdentityTrustEvent>? _trustEvents;

  _Phase _phase = _Phase.idle;
  Future<void>? _loading;
  int _failures = 0;
  DateTime? _retryNotBefore;
  // Moves on at sign-out: a read or write started before belongs to the
  // account that left.
  int _generation = 0;
  String? _userId;
  ContactTrustDocument _doc = ContactTrustDocument.empty();
  Timer? _writeTimer;
  bool _dirty = false;
  bool _disposed = false;

  /// Starts reading the messenger [facade]: its list, messages and sends.
  /// [savedName] says whether a nickname names an account (PeerNames
  /// .accountName); [nicknames] is every nickname by lower-case handle, and
  /// [nicknamesChanged] tells when it changes; [trustEvents] are the identity
  /// trust events (a new device marks its owner changed).
  void attach(
    VeilMessengerController facade, {
    required Stream<IdentityTrustEvent> trustEvents,
    String? Function(String userId, String handle)? savedName,
    Map<String, TrustNickname> Function()? nicknames,
    Listenable? nicknamesChanged,
  }) {
    // A second attach would listen to everything twice.
    assert(_facade == null, 'the trust layer is attached to one messenger, once');
    _facade = facade;
    if (savedName != null) _savedName = savedName;
    if (nicknames != null) _nicknames = nicknames;
    _nicknamesChanged = nicknamesChanged?..addListener(_onNicknames);
    _trustEvents = trustEvents.listen(_onTrustEvent);
    facade.addListener(_onFacade);
    verified.addListener(_onVerified);
    _onFacade();
  }

  /// Whether the document could not be read and the trust layer works as
  /// before it existed: no requests, no risk lines, no claim banner and no
  /// nudge; look-alike checks against verified accounts and the link sheets
  /// still work.
  bool get degraded => _phase == _Phase.degraded;

  /// Whether the document is read and the baseline has run.
  bool get ready => _phase == _Phase.loaded && _doc.baseline;

  /// Whether [conversationId] is a message request: its record is not
  /// accepted, or, once the baseline has run, it has no record yet.
  bool isRequest(String conversationId) {
    if (!ready) return false;
    final record = _doc.chats[conversationId];
    return record == null || record.accepted == null;
  }

  /// Whether nothing that tells the other side what happened here may go
  /// for [conversationId] (read receipts, typing) and nothing is fetched on
  /// its own: a request, or any chat while the document is not read yet or
  /// the baseline is pending.
  bool withholds(String conversationId) {
    if (degraded) return false;
    if (!ready) return true;
    return isRequest(conversationId);
  }

  /// Whether the 1:1 [conversationId] was started by me: from a handle I
  /// typed, or with a handle that had a nickname before the chat was first
  /// seen. False for groups.
  bool startedByMe(String conversationId) {
    final record = _doc.chats[conversationId];
    final chat = _facade?.conversationById(conversationId);
    if (record == null || chat == null || chat.type != ConversationType.direct) return false;
    return record.typed || _namedBefore(chat, record.seen);
  }

  /// Who [userId] (listed as [handle]) is to this phone at [at]: for a 1:1
  /// [chat] the peer, for a group the sender. See [Relationship].
  Relationship relationshipAt(String userId, String handle, {required ConversationPreview chat, required DateTime at}) {
    if (_changedAt(userId, chat, at)) return Relationship.changed;
    if (verified.isVerified(userId)) return Relationship.verified;
    if (_savedAt(userId, handle, at)) return Relationship.saved;
    if (_knownAt(userId, chat, at)) return Relationship.known;
    return Relationship.newContact;
  }

  /// Whether the claim banner was shown in [conversationId] and its peer is
  /// still not verified.
  bool claimHolds(String conversationId) {
    if (!_doc.claims.containsKey(conversationId)) return false;
    final peer = _peerOf(_facade?.conversationById(conversationId));
    return peer == null || !verified.isVerified(peer.userId);
  }

  /// Records that the claim banner showed in [conversationId]; it stays
  /// until the peer is verified.
  Future<void> noteClaim(String conversationId) async {
    if (!_writable || _doc.claims.containsKey(conversationId)) return;
    _doc.claims[conversationId] = _nowMs();
    await _changed(flush: true);
  }

  /// The saved and verified accounts the peer of the 1:1 (or two-person
  /// group) [chat] is compared with, the peer left out; none when the peer
  /// is verified or the group is larger. While [degraded], verified ones
  /// only.
  Iterable<TrustAnchor> anchorsFor(ConversationPreview chat) {
    final peer = _peerOf(chat);
    if (peer == null || verified.isVerified(peer.userId)) return const [];
    final now = _clock();
    final anchors = <String, TrustAnchor>{};
    if (!degraded) {
      for (final MapEntry(key: handle, value: nickname) in _nicknames().entries) {
        final userId = nickname.userId;
        if (userId == null || userId == peer.userId || !_savedAt(userId, handle, now)) continue;
        anchors[userId] = (userId: userId, handle: handle, name: nickname.name, verified: verified.isVerified(userId));
      }
    }
    for (final userId in verified.userIds) {
      if (userId == peer.userId || anchors.containsKey(userId)) continue;
      final handle = _handleOf(userId);
      if (handle == null) continue;
      anchors[userId] = (userId: userId, handle: handle, name: _savedName(userId, handle), verified: true);
    }
    return anchors.values;
  }

  /// Accepts [conversationId] (the request bar's Accept), for good, and
  /// sends the read receipt held back for what was read.
  Future<void> accept(String conversationId) => _accept(conversationId);

  /// Opens the 1:1 with the handle the user typed and accepts it, as
  /// started by me. Null when the messenger could not open it.
  Future<String?> startDirect(String handle) async {
    final facade = _facade;
    if (facade == null) return null;
    final id = await facade.startConversationByHandle(handle);
    if (id == null || !_writable) return id;
    _recordFor(id).typed = true;
    await _accept(id, changed: true);
    return id;
  }

  /// Accepts the group createGroup returned, as created by me.
  Future<void> acceptCreated(String conversationId) async {
    if (!_writable) return;
    _recordFor(conversationId).created = true;
    await _accept(conversationId, changed: true);
  }

  /// A text or file this phone is sending in [conversationId] (the
  /// messenger's onOwnSend): accepts the chat and records the send.
  void noteOwnSend(String conversationId) {
    if (!_writable) return;
    final record = _recordFor(conversationId);
    if (record.sent != null && record.accepted != null) return;
    record.sent ??= _nowMs();
    unawaited(_accept(conversationId, changed: true));
  }

  /// Whether the verify nudge may show for [userId]: fewer than three chat
  /// openings showed it and the user has not verified since.
  bool nudgeAllowed(String userId) {
    if (!ready) return false;
    final count = _doc.nudges[userId] ?? 0;
    return count >= 0 && count < 3;
  }

  /// One more chat opening showed the nudge for [userId].
  Future<void> nudgeShown(String userId) async {
    if (!_writable) return;
    final count = _doc.nudges[userId] ?? 0;
    if (count < 0) return;
    _doc.nudges[userId] = count + 1;
    await _changed();
  }

  /// The user verified [userId] from the nudge: it never shows again.
  Future<void> nudgeDone(String userId) async {
    if (!_writable) return;
    _doc.nudges[userId] = -1;
    await _changed(flush: true);
  }

  /// Writes what is pending now.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (!_dirty || !_writable) return;
    _dirty = false;
    final generation = _generation;
    try {
      await _store.write(_doc);
    } catch (_) {
      // Kept in memory; the next change writes it again.
      if (generation == _generation) _dirty = true;
    }
  }

  // Both providers that hand this out may dispose it; the second does nothing.
  @override
  void dispose() {
    if (_disposed) return;
    unawaited(flush());
    _disposed = true;
    _facade?.removeListener(_onFacade);
    verified.removeListener(_onVerified);
    _nicknamesChanged?.removeListener(_onNicknames);
    unawaited(_trustEvents?.cancel());
    super.dispose();
  }

  // ---------------------------------------------------------------------

  bool get _writable => _phase == _Phase.loaded;

  int _nowMs() => _clock().millisecondsSinceEpoch;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onFacade() {
    final facade = _facade;
    if (facade == null || _disposed) return;
    final userId = facade.localUserId;
    if (userId != _userId) {
      if (_userId != null) _signedOut();
      _userId = userId;
      if (userId != null) {
        unawaited(verified.reload());
        unawaited(_load());
      }
      return;
    }
    if (_phase == _Phase.failed && !_clock().isBefore(_retryNotBefore!)) {
      unawaited(_load());
      return;
    }
    if (_phase == _Phase.loaded) _sync();
  }

  /// Forgets what was read for the account that signed out; nothing still
  /// pending is written. The next sign-in reads the document again.
  void forget() {
    _signedOut();
    _userId = null;
  }

  void _signedOut() {
    _generation += 1;
    _writeTimer?.cancel();
    _writeTimer = null;
    _dirty = false;
    _phase = _Phase.idle;
    _loading = null;
    _failures = 0;
    _retryNotBefore = null;
    _doc = ContactTrustDocument.empty();
    verified.clear();
    _notify();
  }

  Future<void> _load() => _loading ??= _read();

  Future<void> _read() async {
    final generation = _generation;
    _phase = _Phase.loading;
    ContactTrustDocument? stored;
    try {
      stored = await _store.read();
    } catch (_) {
      if (generation != _generation) return;
      _loading = null;
      _failures += 1;
      if (_failures > _retryDelays.length) {
        _phase = _Phase.degraded;
        _log('The contact trust document could not be read; message requests are off until the next sign-in.');
        _notify();
        return;
      }
      _phase = _Phase.failed;
      _retryNotBefore = _clock().add(_retryDelays[_failures - 1]);
      return;
    }
    if (generation != _generation || _disposed) return;
    _doc = stored ?? ContactTrustDocument.empty();
    _phase = _Phase.loaded;
    _noteNicknames();
    _sync();
    // A receipt the wait for the document held back in the open chat.
    final active = _facade?.activeConversationId;
    if (active != null && !withholds(active)) unawaited(_facade?.resendReadReceipt(active));
    _notify();
  }

  // Record keeping, on every messenger change once the document is read.
  void _sync() {
    final facade = _facade!;
    final listed = facade.listedByRelay;
    // Before the first relay list, a baseline still to run waits for it:
    // what the cache shows is not what the relay lists.
    if (!_doc.baseline && !listed) return;
    final now = _nowMs();
    final accepted = <String>[];
    // The baseline accepts every chat it finds: written at once, like any accept.
    final baselineRuns = !_doc.baseline;
    var changed = false;
    final ids = <String>{};
    for (final chat in facade.conversations) {
      ids.add(chat.id);
      var record = _doc.chats[chat.id];
      if (record == null) {
        if (!_doc.baseline) {
          record = ChatTrustRecord.baseline(
            mine0: facade.messagesFor(chat.id).any((message) => message.isMine && !message.isLocalNotice),
          );
        } else {
          record = ChatTrustRecord.seen(now);
          if (chat.type == ConversationType.direct && _namedBefore(chat, now)) {
            record.accepted = now;
            accepted.add(chat.id);
          }
        }
        _doc.chats[chat.id] = record;
        changed = true;
      } else if (listed && record.gone != null) {
        record.gone = null;
        changed = true;
      }
      if (record.accepted == null && _acceptedByOthers(chat)) {
        record.accepted = now;
        accepted.add(chat.id);
        changed = true;
      }
    }
    if (listed) {
      if (!_doc.baseline) {
        _doc.baseline = true;
        changed = true;
      }
      final prune = now - _keepGone.inMilliseconds;
      _doc.chats.removeWhere((_, record) => record.gone != null && record.gone! < prune);
      for (final MapEntry(key: id, value: record) in _doc.chats.entries) {
        if (!ids.contains(id) && record.gone == null) {
          record.gone = now;
          changed = true;
        }
      }
    }
    if (!changed) return;
    unawaited(_changed(flush: baselineRuns || accepted.isNotEmpty));
    for (final id in accepted) {
      unawaited(facade.resendReadReceipt(id));
    }
  }

  // A 1:1 whose peer is verified; a group whose every other listed member
  // is verified, saved or known (through my own 1:1 with them).
  bool _acceptedByOthers(ConversationPreview chat) {
    final now = _clock();
    if (chat.type == ConversationType.direct) {
      final peer = chat.recipientBundle.userId;
      return peer.isNotEmpty && verified.isVerified(peer) && !_changedAt(peer, chat, now);
    }
    final others = [
      for (final member in chat.members)
        if (member.userId != _facade?.localUserId) member,
    ];
    if (others.isEmpty) return false;
    return others.every((member) =>
        verified.isVerified(member.userId) ||
        _savedAt(member.userId, member.handle, now) ||
        _knownThroughDirect(member.userId, now));
  }

  // [changed]: the caller changed the record too, so it is written even
  // when the chat was accepted already.
  Future<void> _accept(String conversationId, {bool changed = false}) async {
    if (!_writable) return;
    final record = _recordFor(conversationId);
    if (record.accepted != null) {
      if (changed) await _changed(flush: true);
      return;
    }
    record.accepted = _nowMs();
    await _changed(flush: true);
    await _facade?.resendReadReceipt(conversationId);
  }

  ChatTrustRecord _recordFor(String conversationId) =>
      _doc.chats.putIfAbsent(conversationId, () => ChatTrustRecord.seen(_nowMs()));

  Future<void> _changed({bool flush = false}) async {
    if (!_writable) return;
    _dirty = true;
    _notify();
    if (flush) {
      await this.flush();
      return;
    }
    _writeTimer ??= Timer(_writeDelay, () => unawaited(this.flush()));
  }

  void _onVerified() {
    if (_phase == _Phase.loaded) _sync();
    _notify();
  }

  void _onNicknames() {
    if (_phase != _Phase.loaded) return;
    _noteNicknames();
  }

  // Each handle with a nickname and no entry gets one now (0 while the
  // baseline is pending: the nickname was there before trust records); a
  // handle whose nickname went loses it, so a later save starts a new week.
  // An empty map may be one not read yet, so it removes nothing.
  void _noteNicknames() {
    final nicknames = _nicknames();
    var changed = false;
    final at = _doc.baseline ? _nowMs() : 0;
    for (final handle in nicknames.keys) {
      if (_doc.named.containsKey(handle)) continue;
      _doc.named[handle] = at;
      changed = true;
    }
    if (nicknames.isNotEmpty) {
      final before = _doc.named.length;
      _doc.named.removeWhere((handle, _) => !nicknames.containsKey(handle));
      changed |= _doc.named.length != before;
    }
    if (changed) unawaited(_changed());
  }

  void _onTrustEvent(IdentityTrustEvent event) {
    if (event is! NewDeviceAdmitted || !_writable) return;
    _doc.changed[event.userId] = _nowMs();
    unawaited(_changed());
  }

  bool _changedAt(String userId, ConversationPreview chat, DateTime at) {
    final facade = _facade;
    if (facade != null) {
      if (facade.pendingIdentityChangeAbout(userId) != null) return true;
      if (chat.type == ConversationType.direct &&
          chat.recipientBundle.userId == userId &&
          facade.peerIdentityInQuestion(chat.id)) {
        return true;
      }
    }
    final since = _doc.changed[userId];
    if (since == null) return false;
    final atMs = at.millisecondsSinceEpoch;
    return since <= atMs && atMs - since < _week.inMilliseconds;
  }

  bool _savedAt(String userId, String handle, DateTime at) {
    if (_savedName(userId, handle) == null) return false;
    final named = _doc.named[handle.toLowerCase()];
    if (named == null) return false;
    return named == 0 || named <= at.subtract(_week).millisecondsSinceEpoch;
  }

  bool _knownAt(String userId, ConversationPreview chat, DateTime at) {
    if (chat.type == ConversationType.direct) return _directKnown(chat.id, at);
    final record = _doc.chats[chat.id];
    if (record != null && (record.created || _acceptedWeekBefore(record, at))) return true;
    return _knownThroughDirect(userId, at);
  }

  bool _knownThroughDirect(String userId, DateTime at) =>
      _facade?.conversations.any((chat) =>
          chat.type == ConversationType.direct && chat.recipientBundle.userId == userId && _directKnown(chat.id, at)) ??
      false;

  bool _directKnown(String conversationId, DateTime at) {
    final record = _doc.chats[conversationId];
    if (record == null) return false;
    return record.mine0 || (record.sent != null && _acceptedWeekBefore(record, at));
  }

  static bool _acceptedWeekBefore(ChatTrustRecord record, DateTime at) {
    final accepted = record.accepted;
    return accepted != null && accepted <= at.subtract(_week).millisecondsSinceEpoch;
  }

  // Whether the 1:1 [chat]'s handle had a nickname (naming its peer, or no
  // account yet) before [seenMs].
  bool _namedBefore(ConversationPreview chat, int seenMs) {
    final handle = chat.peerHandle.toLowerCase();
    final nickname = _nicknames()[handle];
    final named = _doc.named[handle];
    if (nickname == null || named == null || named >= seenMs) return false;
    return nickname.userId == null || nickname.userId == chat.recipientBundle.userId;
  }

  // The one other party of a 1:1 or a two-person group.
  ({String userId, String handle})? _peerOf(ConversationPreview? chat) {
    if (chat == null) return null;
    if (chat.type == ConversationType.direct) {
      final userId = chat.recipientBundle.userId;
      return userId.isEmpty ? null : (userId: userId, handle: chat.peerHandle);
    }
    final others = [
      for (final member in chat.members)
        if (member.userId != _facade?.localUserId) member,
    ];
    return others.length == 1 ? (userId: others.single.userId, handle: others.single.handle) : null;
  }

  // The handle this phone knows [userId] by: the one a 1:1 is bound under,
  // else the one a 1:1 is listed under.
  String? _handleOf(String userId) {
    final facade = _facade;
    if (facade == null) return null;
    for (final peer in facade.boundPeers.values) {
      if (peer.userId == userId) return peer.handle;
    }
    for (final chat in facade.conversations) {
      if (chat.type == ConversationType.direct && chat.recipientBundle.userId == userId) return chat.peerHandle;
    }
    return null;
  }
}

enum _Phase { idle, loading, loaded, failed, degraded }
