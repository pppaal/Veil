import '../crypto/crypto_engine.dart';

// A conversation as the messenger and the encrypted cache both know it.
// Kept in core so the cache can persist it without depending on features.

enum ConversationType { direct, group, channel }

enum MemberRole { owner, admin, member, subscriber }

class GroupMeta {
  const GroupMeta({
    required this.name,
    this.description,
    this.avatarPath,
    this.isPublic = false,
    this.memberCount = 0,
    this.memberLimit = 500,
    this.link,
  });

  final String name;
  final String? description;
  final String? avatarPath;
  final bool isPublic;
  final int memberCount;
  final int memberLimit;
  final String? link;
}

// Lightweight per-member projection used when the client needs to enumerate
// a group's participants — currently for per-peer safety-number verification.
// Does NOT carry key material: identities come from the local pin table, and
// devices from the key directory when a chain key is sealed. Nor a name: the
// relay lists a member as an account and a handle, and what the screens
// call them is the nickname the user gave that handle on this phone.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.handle,
    this.role = MemberRole.member,
  });

  final String userId;
  final String handle;
  final MemberRole role;
}

class ChannelMeta {
  const ChannelMeta({
    required this.name,
    this.description,
    this.avatarPath,
    this.isPublic = false,
    this.subscriberCount = 0,
    this.link,
  });

  final String name;
  final String? description;
  final String? avatarPath;
  final bool isPublic;
  final int subscriberCount;
  final String? link;
}

class ConversationSessionState {
  const ConversationSessionState({
    required this.sessionLocator,
    required this.sessionEnvelopeVersion,
    required this.requiresLocalPersistence,
    required this.sessionSchemaVersion,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteIdentityFingerprint,
    required this.bootstrappedAt,
    this.auditHint,
    this.remoteIdentityPublicKey = '',
  });

  final String sessionLocator;
  final String sessionEnvelopeVersion;
  final bool requiresLocalPersistence;
  final int sessionSchemaVersion;
  final String localDeviceId;
  final String remoteDeviceId;
  final String remoteIdentityFingerprint;
  final DateTime bootstrappedAt;
  final String? auditHint;
  // Identity key the session was bootstrapped against. Empty for sessions
  // created before it was recorded, and for inbound sessions until the first
  // directory answer for the same device pins it.
  final String remoteIdentityPublicKey;

  bool matchesBundle(KeyBundle bundle) => remoteDeviceId == bundle.deviceId;

  bool belongsToLocalDevice(String deviceId) => localDeviceId == deviceId;

  ConversationSessionState withRemoteIdentity(String identityPublicKey) => ConversationSessionState(
        sessionLocator: sessionLocator,
        sessionEnvelopeVersion: sessionEnvelopeVersion,
        requiresLocalPersistence: requiresLocalPersistence,
        sessionSchemaVersion: sessionSchemaVersion,
        localDeviceId: localDeviceId,
        remoteDeviceId: remoteDeviceId,
        remoteIdentityFingerprint: remoteIdentityFingerprint,
        bootstrappedAt: bootstrappedAt,
        auditHint: auditHint,
        remoteIdentityPublicKey: identityPublicKey,
      );
}

class ConversationPreview {
  static const Object _unset = Object();

  ConversationPreview({
    required this.id,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.recipientBundle,
    required this.lastEnvelope,
    required this.updatedAt,
    this.sessionState,
    this.type = ConversationType.direct,
    this.groupMeta,
    this.channelMeta,
    this.memberCount,
    this.members = const [],
    this.lastMessageOrder,
    this.disappearingTimerSeconds,
    this.useSenderKeys = false,
    this.groupEpoch,
  });

  final String id;
  final String peerHandle;

  /// Unused for display, and null from the relay, which lists a peer by
  /// account and handle alone (ConversationMemberSummary). Kept because the
  /// conversation cache stores the column. Screens name the peer by the
  /// nickname the user gave their handle (PeerNames).
  final String? peerDisplayName;
  final KeyBundle recipientBundle;
  final CryptoEnvelope? lastEnvelope;
  final DateTime updatedAt;
  final ConversationSessionState? sessionState;
  final ConversationType type;
  final GroupMeta? groupMeta;
  final ChannelMeta? channelMeta;
  final int? memberCount;
  // All participants of this conversation, populated only for groups.
  // For direct chats this is empty — the single peer lives in
  // peerHandle/recipientBundle. Key material is NOT
  // carried here; resolve per-member KeyBundles on demand.
  final List<GroupMember> members;
  // The relay's conversation order of the last message the list names
  // (lastMessage.conversationOrder); null when it names none. Not cached:
  // the next list brings it. The first list on a new device reads every
  // conversation through it (ReadStateService).
  final int? lastMessageOrder;
  // Default TTL (seconds) applied to newly-sent messages in this
  // conversation. null = disappearing messages disabled.
  final int? disappearingTimerSeconds;
  // Group Sender Keys: true when the server requires `veil-group-v1`
  // envelopes stamped with `groupEpoch` for this group. Always false for
  // direct chats and channels.
  final bool useSenderKeys;
  // Current membership generation (conversations.current_epoch). Null when
  // unknown (e.g. hydrated from cache before the first refresh).
  final int? groupEpoch;

  ConversationPreview copyWith({
    String? id,
    String? peerHandle,
    Object? peerDisplayName = _unset,
    KeyBundle? recipientBundle,
    Object? lastEnvelope = _unset,
    DateTime? updatedAt,
    Object? sessionState = _unset,
    ConversationType? type,
    Object? groupMeta = _unset,
    Object? channelMeta = _unset,
    Object? memberCount = _unset,
    List<GroupMember>? members,
    Object? lastMessageOrder = _unset,
    Object? disappearingTimerSeconds = _unset,
    bool? useSenderKeys,
    Object? groupEpoch = _unset,
  }) {
    return ConversationPreview(
      id: id ?? this.id,
      peerHandle: peerHandle ?? this.peerHandle,
      peerDisplayName:
          identical(peerDisplayName, _unset) ? this.peerDisplayName : peerDisplayName as String?,
      recipientBundle: recipientBundle ?? this.recipientBundle,
      lastEnvelope:
          identical(lastEnvelope, _unset) ? this.lastEnvelope : lastEnvelope as CryptoEnvelope?,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionState:
          identical(sessionState, _unset) ? this.sessionState : sessionState as ConversationSessionState?,
      type: type ?? this.type,
      groupMeta:
          identical(groupMeta, _unset) ? this.groupMeta : groupMeta as GroupMeta?,
      channelMeta:
          identical(channelMeta, _unset) ? this.channelMeta : channelMeta as ChannelMeta?,
      memberCount:
          identical(memberCount, _unset) ? this.memberCount : memberCount as int?,
      members: members ?? this.members,
      lastMessageOrder: identical(lastMessageOrder, _unset) ? this.lastMessageOrder : lastMessageOrder as int?,
      disappearingTimerSeconds: identical(disappearingTimerSeconds, _unset)
          ? this.disappearingTimerSeconds
          : disappearingTimerSeconds as int?,
      useSenderKeys: useSenderKeys ?? this.useSenderKeys,
      groupEpoch: identical(groupEpoch, _unset) ? this.groupEpoch : groupEpoch as int?,
    );
  }
}
