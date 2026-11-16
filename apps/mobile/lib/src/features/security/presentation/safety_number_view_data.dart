import '../../../core/identity/trusted_identity.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/identity_trust.dart';
import '../../conversations/presentation/peer_names.dart';

// What the safety number screen has read before it draws: the member list
// of a group, or one person's number with everything that qualifies it.

sealed class SafetyNumbersViewData {
  const SafetyNumbersViewData();
}

class SafetyDetailData extends SafetyNumbersViewData {
  const SafetyDetailData({
    required this.peer,
    required this.localUserId,
    required this.localKey,
    required this.pin,
    required this.number,
    required this.pendingChange,
    required this.pendingNumber,
    required this.changeElsewhere,
    required this.mayDecline,
    required this.directory,
    required this.isDirect,
  });

  final GroupMember peer;

  /// The nickname the user gave [peer] by [names] (see PeerNames), or null.
  /// Read as the page draws, so a name that loads later still shows.
  String? nameIn(PeerNames names, String conversationId) =>
      isDirect ? names.directName(conversationId, peer.handle) : names.memberName(peer);

  /// What the page calls [peer]: their name, or their handle.
  String titleIn(PeerNames names, String conversationId) => nameIn(names, conversationId) ?? '@${peer.handle}';
  final String localUserId;
  final List<int> localKey;

  /// The pinned identity the number is about; null before any was pinned.
  final TrustedIdentity? pin;
  final String? number;

  /// The identity this conversation is held back on, and its number.
  final PendingIdentityChange? pendingChange;
  final String? pendingNumber;

  /// A change of the peer's identity that another conversation holds for
  /// review, when this one holds none.
  final PendingIdentityChange? changeElsewhere;

  /// Whether the user may keep the pinned identity instead of [pendingChange].
  final bool mayDecline;

  /// How the directory's answer compares with [pin]; null when either is
  /// unknown.
  final SafetyDirectoryAnswer? directory;
  final bool isDirect;
}

enum SafetyDirectoryAnswer {
  matches,

  /// The directory serves the pinned device under another key.
  otherKey,

  /// The directory serves another device than the one [SafetyDetailData.pin]
  /// names: in a direct conversation, not the device it encrypts to.
  otherDevice,
}

class SafetyGroupListData extends SafetyNumbersViewData {
  const SafetyGroupListData({
    required this.groupName,
    required this.members,
    required this.verifiedUserIds,
  });

  final String? groupName;
  final List<GroupMember> members;
  final Set<String> verifiedUserIds;
}
