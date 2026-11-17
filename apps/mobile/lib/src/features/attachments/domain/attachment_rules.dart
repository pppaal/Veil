import 'dart:convert';

import '../../../core/crypto/attachment/attachment_cipher_v2.dart';
import '../../../core/crypto/message_padding.dart';
import '../../../core/util/uuid_v4.dart';

// The rules for photos and files in messages, on both sides: what may be
// sent, what may be fetched, what is drawn and how a sender's file name is
// made safe. Names, types and sizes arrive inside a peer's payload, so a
// hostile sender picks them freely; nothing here trusts them further than
// it must.

/// The largest file sent as it is (the web's FILE_MAX_BYTES).
const int kMaxFileBytes = 25 * 1024 * 1024;

/// The largest photo the web sends (IMAGE_MAX_BYTES), and the largest one
/// this phone fetches by itself.
const int kMaxPhotoBytes = 10 * 1024 * 1024;

/// The largest attachment the relay stores (VEIL_ATTACHMENT_MAX_BYTES by
/// default); a pointer naming more is refused before any request.
const int kMaxAttachmentBytes = 50 * 1024 * 1024;

/// A sent photo's long edge at most, in pixels; it is never upscaled.
const int kPhotoMaxEdge = 1600;
const int kPhotoJpegQuality = 80;

/// The largest photo the phone prepares to send, read from its header: the
/// engine scales a JPEG while it decodes, so memory follows the target size;
/// every other format is decoded whole before it is resized.
const int kMaxJpegSourcePixels = 200 * 1000 * 1000;
const int kMaxOtherSourcePixels = 40 * 1000 * 1000;

/// The largest received photo drawn, read from its header before anything
/// is decoded: a JPEG is decoded scaled, a PNG or WebP at full size first.
const int kMaxJpegRenderPixels = 50 * 1000 * 1000;
const int kMaxJpegRenderSide = 16384;
const int kMaxOtherRenderPixels = 16 * 1000 * 1000;
const int kMaxOtherRenderSide = 8192;

/// The viewer's decode target, long edge at most.
const int kViewerMaxEdge = 4096;

/// The longest name a local Open or Save copy gets, in UTF-8 bytes: under
/// the 255-byte NAME_MAX of ext4 and APFS, with room to spare.
const int kMaxLocalNameBytes = 200;

/// The one attachment scheme this phone opens (pointer v2).
const String kAttachmentAlgorithmV2 = attachmentAlgorithmV2;

/// How many characters a file name keeps (the web's MAX_FILENAME_CHARS).
const int kMaxFileNameChars = 120;

// Bidi embeddings, overrides and isolates (U+202A-202E, U+2066-2069),
// LRM/RLM and C0/C1 controls. A right-to-left override turns
// "invoice\u{202E}fdp.exe" into what reads as "invoiceexe.pdf".
// The controls are regex escapes; the rest are Dart escapes, so the source
// holds no character that changes how it reads.
final RegExp _unsafeFileNameChars =
    RegExp('[\\u0000-\\u001f\\u007f-\\u009f\u{200E}\u{200F}\u{202A}-\u{202E}\u{2066}-\u{2069}]');
final RegExp _extensionPattern = RegExp(r'^[A-Za-z0-9]{1,10}$');

/// Whether [value] may name an attachment: a UUID, as the web requires.
bool isAttachmentId(String value) => isUuidString(value);

/// [name] as the web's sanitizeFilename leaves it: the characters above
/// removed, trimmed, at most 120 characters keeping a real extension of 1
/// to 10 letters or digits; [fallback] when nothing is left.
String sanitizeFileName(String name, {String fallback = 'file'}) {
  final cleaned = name.replaceAll(_unsafeFileNameChars, '').trim();
  final chars = cleaned.runes.toList();
  if (chars.isEmpty) return fallback;
  if (chars.length <= kMaxFileNameChars) return cleaned;
  final extension = _lastExtension(cleaned);
  final suffix = extension.isEmpty ? '' : '.$extension';
  return String.fromCharCodes(chars.take(kMaxFileNameChars - suffix.length)) + suffix;
}

/// The real (last) extension of [name], lower-cased, or '' when it has none
/// (the web's fileExtension): shown next to the name so it cannot hide.
String fileExtension(String name) => _lastExtension(name).toLowerCase();

/// What a file card says a file is: its real extension, upper-cased; null
/// when it has none.
String? fileTypeLabel(String name) {
  final extension = _lastExtension(name);
  return extension.isEmpty ? null : extension.toUpperCase();
}

// As written, so a capped name keeps its extension's case.
String _lastExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  final extension = name.substring(dot + 1);
  return _extensionPattern.hasMatch(extension) ? extension : '';
}

const Map<String, String> _contentTypes = {
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'md': 'text/markdown',
  'rtf': 'application/rtf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'svg': 'image/svg+xml',
  'html': 'text/html',
  'htm': 'text/html',
  'xml': 'application/xml',
  'epub': 'application/epub+zip',
};

/// The content type a file named [name] is sent as, from its extension
/// through a fixed map, else application/octet-stream. A receiver never
/// draws or opens anything by it.
String contentTypeForName(String name) => _contentTypes[fileExtension(name)] ?? 'application/octet-stream';

/// What [bytes] are as an image the app draws: image/jpeg, image/png or
/// image/webp, else null (the web's sniffImageMime). Decided by the bytes,
/// never by a sender's claim.
String? sniffImageType(List<int> bytes) {
  if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (_startsWith(bytes, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) && _startsWith(bytes, const [0x57, 0x45, 0x42, 0x50], at: 8)) {
    return 'image/webp';
  }
  return null;
}

const _photoOrVideoExtensions = {
  'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'tif', 'tiff', 'dng', 'mp4', 'mov', 'm4v', '3gp', //
};
const _heifBrands = {'heic', 'heix', 'mif1', 'msf1'};
const _videoBrands = {'isom', 'iso2', 'mp41', 'mp42', 'qt  ', '3gp4', '3gp5', 'M4V '};

/// Whether a file picked under File is a photo or a video, which keeps any
/// location saved in it when it is sent as it is: [head] (its first bytes)
/// sniff as JPEG, PNG, WebP, HEIF/HEIC, MP4/MOV/3GP or TIFF, or [name]'s
/// extension is one of theirs.
bool looksLikePhotoOrVideo(List<int> head, String name) =>
    _sniffsAsPhotoOrVideo(head) || _photoOrVideoExtensions.contains(fileExtension(name));

/// Whether a received file is an image or a video that Quick Look must
/// never show on iOS (its share sheet offers Save Image and Save Video,
/// which need a permission the app does not ask for): the photo and video
/// test above, plus GIF and BMP.
bool isImageOrVideoForQuickLook(List<int> head, String name) =>
    looksLikePhotoOrVideo(head, name) ||
    _startsWith(head, ascii.encode('GIF87a')) ||
    _startsWith(head, ascii.encode('GIF89a')) ||
    _startsWith(head, ascii.encode('BM')) ||
    const {'gif', 'bmp'}.contains(fileExtension(name));

bool _sniffsAsPhotoOrVideo(List<int> head) {
  if (sniffImageType(head) != null) return true;
  // TIFF, both byte orders (DNG is TIFF too).
  if (_startsWith(head, const [0x49, 0x49, 0x2a, 0x00]) || _startsWith(head, const [0x4d, 0x4d, 0x00, 0x2a])) {
    return true;
  }
  final brands = _ftypBrands(head);
  return brands.any(_heifBrands.contains) || brands.any(_videoBrands.contains);
}

// The major and compatible brands of an ISO base media file's leading ftyp
// box, as far as [head] holds it.
List<String> _ftypBrands(List<int> head) {
  if (head.length < 12 || !_startsWith(head, ascii.encode('ftyp'), at: 4)) return const [];
  final boxSize = (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
  final end = boxSize < 16 ? 16 : (boxSize > head.length ? head.length : boxSize);
  String brandAt(int offset) => String.fromCharCodes(head.sublist(offset, offset + 4));
  return [
    brandAt(8),
    // Bytes 12 to 16 are the minor version; compatible brands follow.
    for (var offset = 16; offset + 4 <= end; offset += 4) brandAt(offset),
  ];
}

/// Whether a received photo whose bytes sniffed as [sniffedType], [width]
/// by [height] by its header, may be decoded: a JPEG up to 50 MP and 16 384
/// px a side, a PNG or WebP up to 16 MP and 8 192 px a side; nothing else.
bool withinRenderLimits(String sniffedType, int width, int height) {
  if (width <= 0 || height <= 0) return false;
  final pixels = width * height;
  final side = width > height ? width : height;
  return switch (sniffedType) {
    'image/jpeg' => pixels <= kMaxJpegRenderPixels && side <= kMaxJpegRenderSide,
    'image/png' || 'image/webp' => pixels <= kMaxOtherRenderPixels && side <= kMaxOtherRenderSide,
    _ => false,
  };
}

/// Whether a picked photo, [width] by [height] by its header, may be
/// prepared: up to 200 MP for a JPEG, 40 MP for any other format.
bool withinSourceLimits({required bool isJpeg, required int width, required int height}) {
  if (width <= 0 || height <= 0) return false;
  return width * height <= (isJpeg ? kMaxJpegSourcePixels : kMaxOtherSourcePixels);
}

/// The most ciphertext a pointer naming [plaintextSize] can have: its
/// Padmé-padded size (with the delimiter byte) plus the GCM tag, never more
/// than the relay stores. A download is cut off past it.
int maxCiphertextBytes(int plaintextSize) {
  final sealed = MessagePadding.padmeLength(plaintextSize + 1) + 16;
  return sealed < kMaxAttachmentBytes ? sealed : kMaxAttachmentBytes;
}

final RegExp _localNameUnsafe = RegExp(r'[/\\:\u0000]');

/// A name for a local Open or Save copy of a file whose sanitized name is
/// [sanitizedName]: path separators, ':' and NUL replaced, leading dots
/// stripped, at most 200 UTF-8 bytes keeping a real extension of 1 to 10
/// letters or digits, cut only between code points; never empty.
String safeLocalFileName(String sanitizedName) {
  var name = sanitizedName.replaceAll(_localNameUnsafe, '_').replaceFirst(RegExp(r'^\.+'), '').trim();
  if (name.isEmpty) name = 'file';
  if (utf8.encode(name).length <= kMaxLocalNameBytes) return name;
  final extension = _lastExtension(name);
  // The extension is ASCII, so its length is its size in bytes.
  final suffix = extension.isEmpty ? '' : '.$extension';
  final stem = name.substring(0, name.length - suffix.length);
  final budget = kMaxLocalNameBytes - suffix.length;
  final kept = StringBuffer();
  var used = 0;
  for (final rune in stem.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > budget) break;
    kept.writeCharCode(rune);
    used += size;
  }
  final cut = kept.toString().trim();
  return '${cut.isEmpty ? 'file' : cut}$suffix';
}

bool _startsWith(List<int> bytes, List<int> prefix, {int at = 0}) {
  if (bytes.length < at + prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}
