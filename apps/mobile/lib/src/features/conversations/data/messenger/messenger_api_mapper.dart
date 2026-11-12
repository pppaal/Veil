import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';

/// An upload ticket the relay issued for one sealed attachment.
typedef UploadTicket = ({
  String attachmentId,
  String storageKey,
  String uploadUrl,
  Map<String, String> headers,
  DateTime expiresAt,
});

/// Typed reading of relay responses. Pure: anything malformed reads as null
/// instead of throwing, and the caller decides what a missing value means.
class MessengerApiMapper {
  const MessengerApiMapper(this._codec);

  final CryptoEnvelopeCodec _codec;

  Map<String, dynamic> encodeEnvelope(CryptoEnvelope envelope) => _codec.encodeApiEnvelope(envelope);

  CryptoEnvelope? envelope(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return _codec.decodeApiEnvelope(raw);
    } catch (_) {
      return null;
    }
  }

  /// A relayed message; [localDeviceId] marks the ones this device sent.
  ChatMessage? message(Object? raw, {required String? localDeviceId}) {
    if (raw
        case {
          'id': final String id,
          'senderDeviceId': final String senderDeviceId,
          'serverReceivedAt': final String rawReceivedAt,
        }) {
      final sentAt = DateTime.tryParse(rawReceivedAt);
      final (deliveredAt, readAt, expiresAt) = (_time(raw['deliveredAt']), _time(raw['readAt']), _time(raw['expiresAt']));
      final clientMessageId = raw['clientMessageId'];
      final conversationOrder = raw['conversationOrder'];
      final envelope = this.envelope(raw);
      if (sentAt == null ||
          envelope == null ||
          deliveredAt == _malformed ||
          readAt == _malformed ||
          expiresAt == _malformed ||
          (clientMessageId != null && clientMessageId is! String) ||
          (conversationOrder != null && conversationOrder is! int)) {
        return null;
      }
      final delivered = deliveredAt as DateTime?;
      final read = readAt as DateTime?;
      return ChatMessage(
        id: id,
        clientMessageId: clientMessageId as String?,
        senderDeviceId: senderDeviceId,
        sentAt: sentAt,
        envelope: envelope,
        conversationOrder: conversationOrder as int?,
        deliveryState: read != null
            ? MessageDeliveryState.read
            : delivered != null
                ? MessageDeliveryState.delivered
                : MessageDeliveryState.sent,
        deliveredAt: delivered,
        readAt: read,
        expiresAt: expiresAt as DateTime?,
        isMine: senderDeviceId == localDeviceId,
      );
    }
    return null;
  }

  /// One page of history; malformed items are left out.
  ({List<ChatMessage> items, String? nextCursor}) messagePage(
    Map<String, dynamic> response, {
    required String? localDeviceId,
  }) {
    final nextCursor = response['nextCursor'];
    return (
      items: [
        for (final raw in _list(response['items']))
          if (message(raw, localDeviceId: localDeviceId) case final message?) message,
      ],
      nextCursor: nextCursor is String ? nextCursor : null,
    );
  }

  /// The conversation list; malformed items are left out. [localHandle]
  /// tells the peer of a 1:1 apart from this user.
  List<ConversationPreview> conversations(Map<String, dynamic> response, {required String? localHandle}) => [
        for (final raw in _list(response['items']))
          if (conversation(raw, localHandle: localHandle) case final conversation?) conversation,
      ];

  /// A relay conversation as a preview with no session and an empty
  /// bundle: the relay knows neither.
  ConversationPreview? conversation(Object? raw, {required String? localHandle}) {
    if (raw
        case {
          'id': final String id,
          'members': final List<dynamic> rawMembers,
        }) {
      final members = [for (final member in rawMembers) _member(member)];
      if (members.isEmpty || members.contains(null)) return null;
      final peer = members.firstWhere((member) => member!.handle != localHandle, orElse: () => members.first)!;
      final type = switch (raw['type']) {
        'group' => ConversationType.group,
        'channel' => ConversationType.channel,
        _ => ConversationType.direct,
      };
      final lastMessage = raw['lastMessage'];
      final lastEnvelope = lastMessage == null ? null : envelope(lastMessage);
      final updatedAt = lastMessage == null
          ? _time(raw['createdAt'])
          : _time(lastMessage is Map<String, dynamic> ? lastMessage['serverReceivedAt'] : null);
      final timer = raw['disappearingTimerSeconds'];
      final epoch = raw['currentEpoch'];
      if ((lastMessage != null && lastEnvelope == null) ||
          updatedAt is! DateTime ||
          (timer != null && timer is! int) ||
          (epoch != null && epoch is! num)) {
        return null;
      }
      final isGroup = type == ConversationType.group;
      return ConversationPreview(
        id: id,
        peerHandle: peer.handle,
        peerDisplayName: peer.displayName,
        recipientBundle: KeyBundle(
          userId: peer.userId,
          deviceId: '',
          handle: peer.handle,
          identityPublicKey: '',
          signedPrekeyBundle: '',
        ),
        lastEnvelope: lastEnvelope,
        updatedAt: updatedAt,
        type: type,
        // Only groups carry the member list; a 1:1 names its peer above.
        members: isGroup ? members.cast<GroupMember>() : const <GroupMember>[],
        disappearingTimerSeconds: timer as int?,
        useSenderKeys: isGroup && raw['useSenderKeys'] == true,
        groupEpoch: isGroup ? (epoch as num?)?.toInt() : null,
      );
    }
    return null;
  }

  /// The id of the conversation a create call answered with.
  String? createdConversationId(Map<String, dynamic> response) => switch (response['conversation']) {
        {'id': final String id} => id,
        _ => null,
      };

  /// The timer the relay applied (null seconds: off), or [requested] when it
  /// echoed no conversation; null when the echo is malformed.
  ({int? seconds})? appliedTimer(Map<String, dynamic> response, {required int? requested}) {
    final conversation = response['conversation'];
    if (conversation == null) return (seconds: requested);
    if (conversation is! Map<String, dynamic>) return null;
    final seconds = conversation['disappearingTimerSeconds'];
    return seconds == null || seconds is int ? (seconds: seconds as int?) : null;
  }

  String? downloadUrl(Map<String, dynamic> response) => switch (response['ticket']) {
        {'downloadUrl': final String url} => url,
        _ => null,
      };

  UploadTicket? uploadTicket(Map<String, dynamic> response) {
    if (response
        case {
          'attachmentId': final String attachmentId,
          'upload': {
            'storageKey': final String storageKey,
            'uploadUrl': final String uploadUrl,
            'expiresAt': final String rawExpiresAt,
          } && final Map<String, dynamic> upload,
        }) {
      final expiresAt = DateTime.tryParse(rawExpiresAt);
      final headers = upload['headers'] ?? const <String, dynamic>{};
      if (expiresAt == null || headers is! Map<String, dynamic>) return null;
      return (
        attachmentId: attachmentId,
        storageKey: storageKey,
        uploadUrl: uploadUrl,
        headers: headers.map((key, value) => MapEntry(key, value.toString())),
        expiresAt: expiresAt,
      );
    }
    return null;
  }

  static GroupMember? _member(Object? raw) => switch (raw) {
        {'userId': final String userId, 'handle': final String handle} =>
          switch (raw['displayName']) {
            final String? displayName => GroupMember(userId: userId, handle: handle, displayName: displayName),
            _ => null,
          },
        _ => null,
      };

  static List<Object?> _list(Object? raw) => raw is List ? raw : const [];

  static const Object _malformed = Object();

  /// A timestamp, null when absent, or [_malformed].
  static Object? _time(Object? raw) => switch (raw) {
        null => null,
        final String value => DateTime.tryParse(value) ?? _malformed,
        _ => _malformed,
      };
}
