/// Whether an attachment goes as a photo (re-encoded on the phone, kind
/// image) or as a file (sent as it is, kind file).
enum OutgoingAttachmentKind { photo, file }

/// What the attach flow hands the messenger to send: a plaintext file in the
/// staging folder, which the outbox owns from then on and deletes once it is
/// sealed.
class OutgoingAttachment {
  const OutgoingAttachment.photo({required this.path, required this.contentType})
      : kind = OutgoingAttachmentKind.photo,
        name = '';

  const OutgoingAttachment.file({required this.path, required this.name, required this.contentType})
      : kind = OutgoingAttachmentKind.file;

  final OutgoingAttachmentKind kind;

  /// The plaintext, under the staging folder.
  final String path;

  /// A file's sanitized name, which is the message's body; '' for a photo.
  final String name;

  /// image/jpeg or image/png for a photo (what was encoded); for a file, from
  /// its name's extension (contentTypeForName).
  final String contentType;
}
