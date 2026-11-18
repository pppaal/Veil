import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/media_prefetch.dart' show opensAttachment;
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

/// The media service as a bubble or the viewer sees it, with the state the
/// test sets: each attachment's [MediaStatus], the photo bytes it hands
/// out, and a record of every fetch, cancel and copy asked of it.
class ScriptedMedia extends ChangeNotifier implements AttachmentMediaService {
  ScriptedMedia({Directory? openRoot}) : _openRoot = openRoot;

  final Directory? _openRoot;
  final Map<MediaKey, MediaStatus> statuses = {};
  final Map<MediaKey, Uint8List> photos = {};

  /// Photos [cachedPhotoBytes] has in memory; the rest come only through
  /// [photoBytes].
  final Set<MediaKey> inMemory = {};

  /// The plaintext of each attachment, for the copies [plaintextFileFor]
  /// makes.
  final Map<MediaKey, Uint8List> plaintexts = {};

  final List<(MediaKey, bool userAsked)> photoRequests = [];
  final List<MediaKey> downloads = [];
  final List<MediaKey> cancels = [];
  final List<(MediaKey, MediaCopyPurpose)> copies = [];
  final List<String> released = [];

  /// Deletes each copy [plaintextFileFor] made before it returns, as its
  /// message expiring at that moment would.
  bool copyGoneOnReturn = false;

  int _evictions = 0;
  bool _inUse = true;

  void setStatus(String conversationId, AttachmentReference reference, MediaState state, {double? progress}) {
    statuses[MediaKey(conversationId, reference)] = MediaStatus(state, progress: progress);
    notifyListeners();
  }

  /// Drops the decrypted photos, as the lock does.
  void evict() {
    inMemory.clear();
    _evictions += 1;
    notifyListeners();
  }

  @override
  int get evictions => _evictions;

  @override
  bool get inUse => _inUse;

  @override
  void setInUse(bool inUse) {
    _inUse = inUse;
    notifyListeners();
  }

  @override
  MediaStatus statusOf(String conversationId, AttachmentReference reference) {
    if (!opensAttachment(reference)) return const MediaStatus(MediaState.unsupported);
    return statuses[MediaKey(conversationId, reference)] ?? const MediaStatus(MediaState.idle);
  }

  @override
  Future<void> refresh(String conversationId, AttachmentReference reference) async {}

  @override
  Future<Uint8List?> photoBytes(String conversationId, AttachmentReference reference,
      {bool userAsked = false, DateTime? expiresAt, DateTime? sentAt}) async {
    final key = MediaKey(conversationId, reference);
    photoRequests.add((key, userAsked));
    return statusOf(conversationId, reference).state == MediaState.ready ? photos[key] : null;
  }

  @override
  Uint8List? cachedPhotoBytes(String conversationId, AttachmentReference reference) {
    final key = MediaKey(conversationId, reference);
    return inMemory.contains(key) ? photos[key] : null;
  }

  @override
  Future<void> download(String conversationId, AttachmentReference reference, {DateTime? expiresAt}) async {
    downloads.add(MediaKey(conversationId, reference));
  }

  @override
  void cancel(String conversationId, AttachmentReference reference) => cancels.add(MediaKey(conversationId, reference));

  @override
  Future<String?> plaintextFileFor(String conversationId, AttachmentReference reference,
      {required String name, required MediaCopyPurpose purpose, bool photo = false, DateTime? expiresAt}) async {
    final key = MediaKey(conversationId, reference);
    copies.add((key, purpose));
    final bytes = plaintexts[key] ?? photos[key];
    final root = _openRoot;
    if (bytes == null || root == null) return null;
    final folder = Directory(p.join(root.path, AttachmentStoragePaths.openFolder, 'copy${copies.length}'))
      ..createSync(recursive: true);
    final file = File(p.join(folder.path, photo ? '$name.jpg' : name))..writeAsBytesSync(bytes);
    if (copyGoneOnReturn) folder.deleteSync(recursive: true);
    return file.path;
  }

  @override
  Future<void> releaseCopy(String path) async {
    released.add(path);
    final folder = Directory(p.dirname(path));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }

  @override
  void noteImageKey(MediaKey key, Object imageKey) {}

  @override
  void evictDecrypted() => evict();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Offline extends RealtimeService {
  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {}

  @override
  void disconnect() {}

  @override
  void emit(String event, Map<String, dynamic> payload) {}
}

/// A messenger offline, whose media is [media].
class ScriptedMediaMessenger extends VeilMessengerController {
  ScriptedMediaMessenger._(CryptoAdapter adapter, this.scripted)
      : super(
          apiClient: VeilApiClient(baseUrl: 'http://relay.invalid/v1'),
          cryptoEngine: adapter.messaging,
          keyBundleCodec: adapter.keyBundles,
          envelopeCodec: adapter.envelopeCodec,
          sessionBootstrapper: adapter.sessions,
          realtimeService: _Offline(),
          cacheService: null,
        );

  factory ScriptedMediaMessenger(ScriptedMedia media) => ScriptedMediaMessenger._(createDefaultCryptoAdapter(), media);

  final ScriptedMedia scripted;

  @override
  AttachmentMediaService get media => scripted;
}
