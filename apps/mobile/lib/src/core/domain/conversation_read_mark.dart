// What has been read of one conversation on this phone. Kept in core so the
// cache can store it without depending on features.

/// The conversation order of the newest relayed message read here, and
/// whether the user marked the chat unread. Unread counts are derived from
/// it and the loaded messages; nothing about them is stored, and nothing of
/// it leaves the phone.
class ConversationReadMark {
  const ConversationReadMark({this.readThrough, this.markedUnread = false});

  /// The newest relayed message read here, by its conversation order; null
  /// while nothing has been.
  final int? readThrough;

  /// The user chose "Mark as unread"; opening the chat or "Mark as read"
  /// clears it.
  final bool markedUnread;

  @override
  bool operator ==(Object other) =>
      other is ConversationReadMark && other.readThrough == readThrough && other.markedUnread == markedUnread;

  @override
  int get hashCode => Object.hash(readThrough, markedUnread);

  @override
  String toString() => 'ConversationReadMark(readThrough: $readThrough, markedUnread: $markedUnread)';
}
