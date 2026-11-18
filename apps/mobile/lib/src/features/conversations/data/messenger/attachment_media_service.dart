import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/media_index.dart';
import '../../../attachments/data/attachment_decrypt.dart';
import '../../../attachments/data/attachment_storage_paths.dart';
import '../../../attachments/data/decrypted_media_cache.dart';
import '../../../attachments/data/media_blob_store.dart';
import '../../../attachments/data/media_cleanup.dart';
import '../../../attachments/data/media_prefetch.dart';
import '../../../attachments/domain/attachment_rules.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

export '../../../attachments/data/decrypted_media_cache.dart' show MediaKey;
export '../../../attachments/data/media_cleanup.dart' show MediaCopyPurpose;
export '../../../attachments/data/media_prefetch.dart' show MediaState, MediaStatus;

/// Photos and files in messages: prefetch, download, decrypt, keep sealed,
/// open. Blobs are fetched capped and kept sealed once their digest
/// matches (D33, D35); a photo that arrives is fetched at once but decrypted
/// only when shown, into memory (D25, D32, D36); a file waits for a tap and
/// is decrypted only into a short-lived copy for Open or Save (D38).
/// MessengerServices.dispose disposes it, which stops its timers and
/// transfers.
class AttachmentMediaService extends ChangeNotifier implements MessengerStateObserver {
  AttachmentMediaService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required MessengerOperationRunner ops,
    required MessageContentService contents,
    required AttachmentStoragePaths paths,
    required this.blobs,
    required this.autoDownloadWithheld,
    required this.pendingAttachmentIds,
    required DateTime Function() now,
  })  : _store = store,
        _session = session,
        _ops = ops,
        _contents = contents,
        _now = now {
    cleanup = MediaCleanup(
        blobs: blobs, paths: paths, now: now, pendingAttachmentIds: pendingAttachmentIds, onEntryDeleted: _forgetEntry);
    _fetcher = SealedBlobFetcher(api: apiClient, blobs: blobs, serial: cleanup.serial);
    _prefetch = MediaPrefetch(slots: _slots, fetch: _prefetchOne, withheld: autoDownloadWithheld);
    // No decrypted copy outlives the process that made it.
    unawaited(cleanup.purgeCopies());
  }

  /// Sealed blobs on the phone, under random names.
  final MediaBlobStore blobs;

  /// Whether nothing in [conversationId] may be fetched on its own: who its
  /// peer is waits for the user, or it is a 1:1 with someone blocked
  /// (MessengerServices.autoDownloadWithheld).
  final bool Function(String conversationId) autoDownloadWithheld;

  /// The attachment ids of uploads still pending, whose blobs no cleanup
  /// may take (OutboxService.pendingAttachmentIds).
  final Set<String> Function() pendingAttachmentIds;

  /// The media folder's and veil_open's rules (D37, D38).
  late final MediaCleanup cleanup;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final MessengerOperationRunner _ops;
  final MessageContentService _contents;
  final DateTime Function() _now;
  late final SealedBlobFetcher _fetcher;
  final DecryptedMediaCache _decrypted = DecryptedMediaCache();
  final TransferSlots _slots = TransferSlots();
  late final MediaPrefetch _prefetch;
  final Map<MediaKey, MediaStatus> _status = {};
  final Map<MediaKey, Future<String?>> _fetches = {};
  final Map<MediaKey, Future<Uint8List?>> _opening = {};
  final Map<MediaKey, AttachmentUploadCancellationSignal> _cancels = {};
  final Map<MediaKey, int> _integrityFailures = {};
  final Set<String> _scansScheduled = {};
  // Content stored before this is what the cache held, not something that
  // just arrived: only arrivals are fetched by themselves.
  DateTime _arrivalsSince = DateTime.now();
  bool _started = false;
  bool _disposed = false;

  /// Whether this version opens [reference] (opensAttachment).
  static bool opens(AttachmentReference reference) => opensAttachment(reference);

  MediaStatus statusOf(String conversationId, AttachmentReference reference) {
    if (!opens(reference)) return const MediaStatus(MediaState.unsupported);
    final key = MediaKey(conversationId, reference);
    return _status[key] ??
        (_prefetch.isQueued(key) ? const MediaStatus(MediaState.downloading) : const MediaStatus(MediaState.idle));
  }

  /// Looks for [reference]'s blob on the phone, so a card can say it is
  /// ready without a fetch.
  Future<void> refresh(String conversationId, AttachmentReference reference) async {
    if (!opens(reference)) return;
    final key = MediaKey(conversationId, reference);
    final found = _status[key] == null && await _blobPath(conversationId, reference) != null;
    if (found && _status[key] == null) _set(key, MediaState.ready);
  }

  /// The decrypted photo [reference] points at: from memory, else its blob
  /// on the phone (decrypted in an isolate), else fetched, which only a tap
  /// ([userAsked]) does here: otherwise a missing blob is queued by the
  /// prefetch rules and null comes back, as it does while the app is not in
  /// use. Null too when it cannot be shown ([statusOf] says why).
  Future<Uint8List?> photoBytes(String conversationId, AttachmentReference reference,
      {bool userAsked = false, DateTime? expiresAt, DateTime? sentAt}) {
    if (!opens(reference) || isExpired(expiresAt)) return Future.value();
    final key = MediaKey(conversationId, reference);
    final cached = _decrypted.get(key);
    if (cached != null) return Future.value(cached);
    if (!_inUse && !userAsked) return Future.value();
    late final Future<Uint8List?> opening;
    opening = _opening[key] ??
        _openPhoto(key, conversationId, reference, userAsked, expiresAt, sentAt, _evictions).whenComplete(() {
          if (identical(_opening[key], opening)) _opening.remove(key);
        });
    return _opening[key] = opening;
  }

  /// The decrypted photo when it is in memory now; nothing else is tried.
  Uint8List? cachedPhotoBytes(String conversationId, AttachmentReference reference) =>
      opens(reference) ? _decrypted.get(MediaKey(conversationId, reference)) : null;

  /// Bumped whenever decrypted photos are dropped from memory (the lock,
  /// a sign-out): whatever holds one decoded drops it too.
  int get evictions => _evictions;
  int _evictions = 0;

  /// Fetches [reference]'s sealed blob because the user tapped.
  Future<void> download(String conversationId, AttachmentReference reference, {DateTime? expiresAt}) async {
    if (opens(reference)) await _fetch(MediaKey(conversationId, reference), conversationId, reference, expiresAt);
  }

  /// Stops [reference]'s fetch, a tap still waiting for a transfer slot
  /// too (nothing is fetched or opened for it then); a tap starts it again.
  void cancel(String conversationId, AttachmentReference reference) {
    final key = MediaKey(conversationId, reference);
    _prefetch.remove(key);
    final signal = _cancels[key]?..cancel();
    if (signal != null && _status[key]?.state == MediaState.downloading) _set(key, MediaState.idle);
  }

  /// A decrypted copy of [reference] for Open or Save at
  /// `veil_open/<random>/<name>` (D38), fetched first if its blob is not on
  /// the phone. [name] is made safe here; a [photo] gets the extension its
  /// bytes call for. Null when it could not be made, when its message has
  /// expired, or when the app locked before it was ready. Give it back with
  /// [releaseCopy] as soon as it is not needed.
  Future<String?> plaintextFileFor(String conversationId, AttachmentReference reference,
      {required String name, required MediaCopyPurpose purpose, bool photo = false, DateTime? expiresAt}) async {
    if (!opens(reference) || isExpired(expiresAt)) return null;
    final key = MediaKey(conversationId, reference);
    final evictions = _evictions;
    for (var attempt = 0; attempt < 2; attempt++) {
      final blob =
          await _blobPath(conversationId, reference) ?? await _fetch(key, conversationId, reference, expiresAt);
      if (blob == null || _disposed) return null;
      try {
        final path = await cleanup.decryptCopy(
          conversationId: conversationId,
          reference: reference,
          blob: blob,
          safeName: safeLocalFileName(sanitizeFileName(name)),
          purpose: purpose,
          photo: photo,
        );
        // Locked (or signed out), expired or taken meanwhile: no copy outlives that.
        if (evictions == _evictions && await cleanup.stillHeld(conversationId, reference, expiresAt)) return path;
        await releaseCopy(path);
        return null;
      } on AttachmentOpenException {
        // Damaged on the phone: fetched once more.
        if (!await _openFailed(key, conversationId, reference, blob)) return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Deletes the copy [plaintextFileFor] made at [path].
  Future<void> releaseCopy(String path) => cleanup.deleteCopy(path).catchError((Object _) {});

  /// Notes that the image cache holds [imageKey] for [key], so it goes when
  /// the blob does.
  void noteImageKey(MediaKey key, Object imageKey) => _decrypted.noteImageKey(key, imageKey);

  /// Drops every decrypted byte held in memory, the decoded images, and
  /// every Save copy: the session locked.
  void evictDecrypted() {
    _decrypted.clear();
    _opening.clear();
    _evictions += 1;
    unawaited(cleanup.deleteSaveCopies().catchError((Object _) {}));
    if (!_disposed) notifyListeners();
  }

  /// Whether the app is in front and unlocked (the app says so through
  /// [setInUse]); media work runs only then.
  bool get inUse => _inUse;
  bool _inUse = false;

  void setInUse(bool inUse) {
    final returned = inUse && !_inUse;
    _inUse = inUse;
    if (_disposed) return;
    if (inUse) _ensureStarted();
    _prefetch.setRunning(inUse);
    cleanup.appStateChanged();
    if (!inUse) unawaited(blobs.flushRecency().catchError((Object _) {}));
    // Photos that waited for the app to come back may open now.
    if (returned) notifyListeners();
  }

  /// Forgets everything held for the identity that left.
  void clear() {
    _cancelTransfers();
    _fetches.clear();
    _opening.clear();
    _status.clear();
    _integrityFailures.clear();
    _decrypted.clear();
    _evictions += 1;
    _prefetch..clear()..setRunning(_inUse);
    cleanup.reset();
    _started = false;
    _arrivalsSince = DateTime.now();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTransfers();
    _prefetch.clear();
    cleanup.dispose();
    super.dispose();
  }

  @override
  void conversationsChanged() {
    if (_disposed) return;
    _ensureStarted();
    unawaited(cleanup.conversationsListed(_store.conversations.map((c) => c.id), cached: _store.hydratedIds));
  }

  @override
  void messagesChanged(String conversationId) {
    if (_disposed) return;
    _ensureStarted();
    cleanup.noteMessagesChanged();
    // After the step that merged them, which also started their decrypts:
    // reading them then never decrypts one out of turn.
    if (_scansScheduled.add(conversationId)) {
      scheduleMicrotask(() {
        _scansScheduled.remove(conversationId);
        unawaited(_queueArrivals(conversationId));
      });
    }
  }

  @override
  void pagingChanged(String conversationId) {}

  // At the first sign of a signed-in store: orphans, the expiry sweep, the cap.
  void _ensureStarted() {
    if (_started || _session.signedIn == null) return;
    _started = true;
    unawaited(cleanup.start());
  }

  // Queues the photos that just arrived in [conversationId] (D25).
  Future<void> _queueArrivals(String conversationId) async {
    final generation = _session.generation;
    final arrived = await _prefetch.queueArrivals(conversationId, _store.messagesOf(conversationId),
        read: _contents.read, stored: _contents.storedFor, opens: opens, since: _arrivalsSince, now: _now,
        stillWanted: () => !_disposed && generation == _session.generation);
    if (arrived && !_disposed) notifyListeners();
  }

  Future<void> _prefetchOne(PrefetchItem item) async {
    if (await _blobPath(item.conversationId, item.reference) != null) return _set(item.key, MediaState.ready);
    await _fetch(item.key, item.conversationId, item.reference, item.expiresAt, inSlot: true);
  }

  Future<Uint8List?> _openPhoto(MediaKey key, String conversationId, AttachmentReference reference, bool userAsked,
      DateTime? expiresAt, DateTime? sentAt, int evictions) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      var blob = await _blobPath(conversationId, reference);
      if (blob == null && !userAsked) {
        _queueOnView(key, conversationId, reference, expiresAt, sentAt);
        return null;
      }
      blob ??= await _fetch(key, conversationId, reference, expiresAt);
      if (blob == null) return null;
      final Uint8List bytes;
      try {
        bytes = await openPhoto(reference, blob);
      } on AttachmentOpenException catch (error) {
        if (error.failure == AttachmentOpenFailure.unsupported) return _set(key, MediaState.unsupported);
        // Damaged on the phone: fetched once more, by the same rules.
        if (!await _openFailed(key, conversationId, reference, blob)) return null;
        continue;
      } on FileSystemException {
        // Taken by a sweep meanwhile.
        continue;
      }
      // The bytes decide (D34): a header past the render limits is never
      // decoded.
      if (!await isDrawablePhoto(bytes)) return _set(key, MediaState.unsupported);
      // Locked while it decrypted, expired, or its blob went meanwhile (a
      // cancelled send, a sweep): memory stays as empty as that left it (D36).
      if (evictions != _evictions || !await cleanup.stillHeld(conversationId, reference, expiresAt)) return null;
      _decrypted.put(key, bytes);
      _set(key, MediaState.ready);
      return bytes;
    }
    return null;
  }

  // A photo on screen whose blob is not here: fetched by itself by the same
  // rules as one that just arrived, or left for a tap.
  void _queueOnView(
      MediaKey key, String conversationId, AttachmentReference reference, DateTime? expiresAt, DateTime? sentAt) {
    final state = _status[key]?.state;
    if (state != null && state != MediaState.idle && state != MediaState.ready) return;
    if (_prefetch.isQueued(key) || reference.sizeBytes > kMaxPhotoBytes || isExpired(expiresAt)) return;
    _status.remove(key);
    final item = PrefetchItem(
        key: key, conversationId: conversationId, reference: reference, sentAt: sentAt ?? _now(), expiresAt: expiresAt);
    if (_prefetch.enqueue(item)) notifyListeners();
  }

  // A blob on the phone did not open. One whose digest no longer matches
  // was damaged here: it goes and true says to fetch it again, which does
  // not count toward gone. One that matches did not open with its
  // pointer's key, which counts: failed once, gone the second time.
  Future<bool> _openFailed(MediaKey key, String conversationId, AttachmentReference reference, String blob) async {
    if (await digestMatches(blob, reference.sha256).catchError((Object _) => false)) {
      _integrityFailed(key);
      return false;
    }
    await cleanup.deleteEntryFor(conversationId, reference.attachmentId, reference.sha256);
    _status.remove(key);
    return true;
  }

  void _integrityFailed(MediaKey key) {
    final failures = _integrityFailures[key] = (_integrityFailures[key] ?? 0) + 1;
    _set(key, failures >= 2 ? MediaState.gone : MediaState.failed);
  }

  // One fetch per blob at a time, a cancelled one aside, its cancel signal set
  // at once. A tap waits for a slot, before prefetches; a prefetch holds one.
  Future<String?> _fetch(MediaKey key, String conversationId, AttachmentReference reference, DateTime? expiresAt,
      {bool inSlot = false}) {
    final running = _fetches[key];
    if (running != null && !(_cancels[key]?.isCanceled ?? false)) return running;
    if (!inSlot) _prefetch.remove(key);
    final state = _status[key]?.state;
    // A message that expired is fetched no more (D37).
    if (state == MediaState.gone || state == MediaState.unsupported || isExpired(expiresAt)) return Future.value();
    _set(key, MediaState.downloading);
    final signal = _cancels[key] = AttachmentUploadCancellationSignal();
    Future<String?> transfer() => _transfer(key, conversationId, reference, expiresAt, signal);
    late final Future<String?> fetch;
    fetch = (inSlot ? transfer() : _slots.run(transfer)).whenComplete(() {
      if (identical(_fetches[key], fetch)) _fetches.remove(key);
    });
    return _fetches[key] = fetch;
  }

  Future<String?> _transfer(MediaKey key, String conversationId, AttachmentReference reference, DateTime? expiresAt,
      AttachmentUploadCancellationSignal signal) async {
    // Stopped while it waited for its slot: cancel() said so.
    if (signal.isCanceled) return null;
    final session = _session.authed;
    if (session == null || _disposed) return _set(key, MediaState.failed);
    final generation = _session.generation;
    bool stillWanted() => !_disposed && generation == _session.generation && !signal.isCanceled &&
        !cleanup.hasLeft(conversationId) && !isExpired(expiresAt);
    final result = await _fetcher.fetch(
      accessToken: session.accessToken,
      conversationId: conversationId,
      reference: reference,
      signal: signal,
      stillWanted: stillWanted,
      expiresAt: expiresAt,
      onProgress: (share) => _set(key, MediaState.downloading, progress: share),
    );
    if (identical(_cancels[key], signal)) _cancels.remove(key);
    if (_disposed || generation != _session.generation) return null;
    final error = result.error;
    if (error != null) await _ops.handleSecurityException(error);
    switch (result.failure) {
      case null:
        _set(key, MediaState.ready);
        unawaited(cleanup.enforceCap());
        return result.path;
      case FetchFailure.integrity:
        _integrityFailed(key);
      case FetchFailure.gone:
        _set(key, MediaState.gone);
      case FetchFailure.canceled:
        // A cancel already said so, and a tap since may be fetching again.
        if (!signal.isCanceled) _set(key, MediaState.idle);
      case FetchFailure.failed:
        _set(key, MediaState.failed);
    }
    return null;
  }

  /// Whether a message that expires at [expiresAt] has expired.
  bool isExpired(DateTime? expiresAt) => cleanup.expired(expiresAt);

  Future<String?> _blobPath(String conversationId, AttachmentReference reference) =>
      blobs.pathOf(conversationId, reference.attachmentId, reference.sha256).catchError((Object _) => null);

  void _cancelTransfers() => _cancels..values.toList().forEach((signal) => signal.cancel())..clear();

  // An index entry was deleted (expiry, a chat that left, the cap, a
  // damaged file): its decrypted bytes and decoded images go with it.
  void _forgetEntry(MediaIndexEntry entry) {
    bool names(MediaKey key) => key.names(entry.conversationId, entry.attachmentId, entry.digest);
    _decrypted.removeWhere(names);
    _status.removeWhere((key, _) => names(key));
    if (!_disposed) notifyListeners();
  }

  // Null, so a step that ends on a state can return it.
  Null _set(MediaKey key, MediaState state, {double? progress}) {
    if (_disposed) return;
    _status[key] = MediaStatus(state, progress: progress);
    notifyListeners();
  }
}
