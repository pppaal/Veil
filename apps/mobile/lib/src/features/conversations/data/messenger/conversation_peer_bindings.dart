import 'dart:convert';

import '../../../../core/identity/issued_handle.dart';
import '../../../../core/storage/secure_storage_service.dart';

/// The contact a 1:1 conversation is with.
class ConversationPeer {
  const ConversationPeer({required this.userId, required this.handle});

  final String userId;
  final String handle;
}

/// Why a 1:1 conversation that is not bound yet admits no identity until
/// the user says the account it is listed with is the one they want.
enum PeerAccountHoldReason {
  /// Listed under a handle this device bound to another account.
  otherAccount,

  /// Listed under a handle no honest relay issues (see isIssuableHandle).
  unissuedHandle,
}

class PeerAccountHold {
  const PeerAccountHold(this.reason, {this.known});

  final PeerAccountHoldReason reason;

  /// The account this device knows under the same handle, for
  /// [PeerAccountHoldReason.otherAccount].
  final ConversationPeer? known;
}

/// Thrown when a send needs an identity for a conversation held by a
/// [PeerAccountHold]. Scoped to that conversation: the chat shows it.
class PeerAccountHeldException implements Exception {
  const PeerAccountHeldException(this.conversationId, this.hold);

  final String conversationId;
  final PeerAccountHold hold;

  @override
  String toString() => 'This chat is listed under a name this device knows as another account. '
      'Confirm the account before sending.';
}

/// The members a group was last shown with on this device, and how many
/// changes to them it has announced. The count is this device's own: the
/// relay's epoch cannot tell a member removed and added back from one never
/// removed, so it does not name a change.
class GroupMembership {
  const GroupMembership(this.members, {this.changes = 0});

  final Set<String> members;
  final int changes;

  bool sameMembers(Set<String> other) => members.length == other.length && members.containsAll(other);
}

/// Whom each 1:1 conversation is with, recorded once it has a session and
/// never changed after that.
///
/// The ratchet session stays with its conversation id for as long as the
/// device keeps it, and a direct conversation never changes members. A
/// server list that left the conversation out once and then lists it with
/// another user, or as a group, would otherwise have this device show one
/// contact while it reads and writes the other's session. The bindings live
/// in the keystore, apart from the conversation cache the relay's lists
/// overwrite.
///
/// A binding also ties a handle to the account it was bound with. The user
/// sees handles, never user ids, and pins and verification are keyed on the
/// user id: so a conversation that is not bound yet is held ([holdFor])
/// while its listed handle is one this device bound to another account, or
/// one no honest relay issues. Until the user acknowledges that account
/// (which binds it), no identity is pinned, installed or sealed to for it.
class ConversationPeerBindings {
  ConversationPeerBindings({ScopedSecureStore? store}) : _store = store;

  static const _documentKey = 'direct_peers.v1';
  static const _groupsKey = 'group_members.v1';

  final ScopedSecureStore? _store;
  // What [holdFor] last found, for the views to read synchronously.
  final Map<String, PeerAccountHold> _holds = {};
  // Shared by every caller, so a binding recorded while the first read is
  // still in flight is not replaced by a second, older copy of the document.
  Future<Map<String, ConversationPeer>>? _bound;
  // Set when the stored document cannot be read. Nothing is written over it
  // then: that would drop every binding it holds.
  bool _unreadable = false;
  Future<Map<String, GroupMembership>>? _groups;

  /// What each group was last shown with on this device, by conversation id.
  /// Kept with the bindings, apart from the conversation cache, so a change
  /// the relay made while the app was closed is still told apart from the
  /// first listing of a group.
  Future<Map<String, GroupMembership>> groupMembers() async => Map.unmodifiable(await _loadGroups());

  /// Records [memberships] as what each of those groups is shown with now.
  /// A record that could not be read is replaced: it holds nothing the
  /// device can still use, and keeping it would make every later start take
  /// each group for a first listing and announce nothing.
  Future<void> recordGroupMembers(Map<String, GroupMembership> memberships) async {
    if (memberships.isEmpty) return;
    final recorded = await _loadGroups();
    recorded.addAll(memberships);
    await _store?.write(_groupsKey, json.encode({
      for (final MapEntry(key: conversationId, value: membership) in recorded.entries)
        conversationId: {'members': membership.members.toList()..sort(), 'changes': membership.changes},
    }));
  }

  /// Every binding recorded so far, by conversation id.
  Future<Map<String, ConversationPeer>> all() async => Map.unmodifiable(await _load());

  /// Records whom each conversation in [peers] is with, unless it is bound
  /// already: a binding is never replaced.
  Future<void> bindAll(Map<String, ConversationPeer> peers) async {
    final bound = await _load();
    final fresh = {
      for (final entry in peers.entries)
        if (!bound.containsKey(entry.key) && entry.value.userId.isNotEmpty) entry.key: entry.value,
    };
    if (fresh.isEmpty) return;
    bound.addAll(fresh);
    if (_unreadable) return;
    try {
      await _store?.write(_documentKey, json.encode({
        for (final entry in bound.entries) entry.key: {'userId': entry.value.userId, 'handle': entry.value.handle},
      }));
    } catch (_) {
      // Not recorded, so not bound here either: a conversation held for its
      // handle stays held rather than open only until the next start.
      for (final MapEntry(:key, :value) in fresh.entries) {
        if (identical(bound[key], value)) bound.remove(key);
      }
      rethrow;
    }
  }

  /// Why the 1:1 [conversationId], listed with [listed], admits no identity
  /// yet: it is not bound, and its handle is one this device bound to
  /// another account, or one no honest relay issues. Null once it is bound,
  /// or when nothing about its handle conflicts. Kept for [heldNow].
  Future<PeerAccountHold?> holdFor(String conversationId, ConversationPeer listed) async {
    final bound = await _load();
    PeerAccountHold? hold;
    if (!bound.containsKey(conversationId)) {
      if (!isIssuableHandle(listed.handle)) {
        hold = const PeerAccountHold(PeerAccountHoldReason.unissuedHandle);
      } else {
        final handle = listed.handle.toLowerCase();
        final known = bound.values
            .where((peer) => peer.handle.toLowerCase() == handle && peer.userId != listed.userId)
            .firstOrNull;
        if (known != null) hold = PeerAccountHold(PeerAccountHoldReason.otherAccount, known: known);
      }
    }
    if (hold == null) {
      _holds.remove(conversationId);
    } else {
      _holds[conversationId] = hold;
    }
    return hold;
  }

  /// What [holdFor] last found for [conversationId].
  PeerAccountHold? heldNow(String conversationId) => _holds[conversationId];

  /// The user chose to talk to the account [conversationId] is listed with,
  /// although a hold was raised: it is bound to [listed], and so no longer
  /// held.
  Future<void> acknowledge(String conversationId, ConversationPeer listed) async {
    await bindAll({conversationId: listed});
    _holds.remove(conversationId);
  }

  /// Drops what was read for the previous identity; the stored bindings are
  /// wiped with the rest of the device state.
  void reset() {
    _bound = null;
    _unreadable = false;
    _groups = null;
    _holds.clear();
  }

  Future<Map<String, GroupMembership>> _loadGroups() async {
    final loading = _groups ??= _readGroups();
    try {
      return await loading;
    } catch (_) {
      if (identical(_groups, loading)) _groups = null;
      rethrow;
    }
  }

  Future<Map<String, GroupMembership>> _readGroups() async {
    final raw = await _store?.read(_groupsKey);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          key: switch (value) {
            // Members only, as the first version of this record kept them.
            List<dynamic>() => GroupMembership(value.cast<String>().toSet()),
            _ => GroupMembership(
                ((value as Map<String, dynamic>)['members'] as List<dynamic>).cast<String>().toSet(),
                changes: value['changes'] as int,
              ),
          },
      };
    } on Object {
      return {};
    }
  }

  Future<Map<String, ConversationPeer>> _load() async {
    final loading = _bound ??= _read();
    try {
      return await loading;
    } catch (_) {
      // A keystore error is retried by the next call.
      if (identical(_bound, loading)) _bound = null;
      rethrow;
    }
  }

  Future<Map<String, ConversationPeer>> _read() async {
    final raw = await _store?.read(_documentKey);
    if (raw == null) return {};
    final decoded = _tryDecode(raw);
    if (decoded == null) {
      _unreadable = true;
      return {};
    }
    return decoded;
  }

  static Map<String, ConversationPeer>? _tryDecode(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return {
        for (final entry in decoded.entries)
          entry.key: ConversationPeer(
            userId: (entry.value as Map<String, dynamic>)['userId'] as String,
            handle: (entry.value as Map<String, dynamic>)['handle'] as String,
          ),
      };
    } on Object {
      return null;
    }
  }
}
