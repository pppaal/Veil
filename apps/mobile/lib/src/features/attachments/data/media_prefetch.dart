import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/domain/chat_message.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/storage/conversation_cache_service.dart';
import '../domain/attachment_rules.dart';
import 'attachment_decrypt.dart';
import 'decrypted_media_cache.dart';
import 'media_blob_store.dart';

/// Whether this version opens [reference]: pointer v2, a UUID id, at most
/// 50 MiB (D31, D33). Nothing else is ever requested.
bool opensAttachment(AttachmentReference reference) =>
    reference.algorithmHint == kAttachmentAlgorithmV2 &&
    isAttachmentId(reference.attachmentId) &&
    reference.sizeBytes >= 0 &&
    reference.sizeBytes <= kMaxAttachmentBytes;

/// Where an attachment of a message stands on this phone.
enum MediaState {
  /// Not here, and not on its way: a tap fetches it.
  idle,

  /// On its way (or waiting for a transfer slot).
  downloading,

  /// Its sealed blob is on this phone.
  ready,

  /// The last fetch failed; a tap tries again.
  failed,

  /// The server no longer has it for this phone, or it never opened twice
  /// running.
  gone,

  /// This version cannot open it.
  unsupported,
}

@immutable
class MediaStatus {
  const MediaStatus(this.state, {this.progress});

  final MediaState state;

  /// The share fetched while [MediaState.downloading]; null while unknown.
  final double? progress;
}

/// Why fetching a sealed blob did not keep it.
enum FetchFailure {
  /// The bytes are not the blob the pointer names (its digest).
  integrity,

  /// The server says it is not there for this phone (D31).
  gone,

  /// Network, storage or server trouble; worth a retry.
  failed,

  /// The user stopped it.
  canceled,
}

/// Fetches one sealed blob (D33): a download ticket, then at once the GET,
/// capped at what the pointer can hold; a GET refused (403 or 404) gets one
/// fresh ticket. The bytes are kept only once their digest matches, as a
/// part file renamed into the media store. Nothing is decrypted. The
/// rename runs through [serial] (MediaCleanup.serial), so a sweep listing
/// the folder never takes a blob committed meanwhile for an orphan.
class SealedBlobFetcher {
  SealedBlobFetcher({
    required VeilApiClient api,
    required MediaBlobStore blobs,
    required Future<String> Function(Future<String> Function() step) serial,
  })  : _api = api,
        _blobs = blobs,
        _serial = serial;

  final VeilApiClient _api;
  final MediaBlobStore _blobs;
  final Future<String> Function(Future<String> Function() step) _serial;

  /// The kept blob's path, or the [FetchFailure] with what caused it.
  /// [stillWanted] is asked before anything is kept: false drops it (the
  /// identity that asked is gone).
  Future<({String? path, FetchFailure? failure, Object? error})> fetch({
    required String accessToken,
    required String conversationId,
    required AttachmentReference reference,
    required AttachmentUploadCancellationSignal signal,
    required bool Function() stillWanted,
    DateTime? expiresAt,
    void Function(double share)? onProgress,
  }) async {
    final cap = maxCiphertextBytes(reference.sizeBytes);
    var reported = 0.0;
    Future<String> ticket() async {
      final answer = await _api.getDownloadTicket(accessToken, reference.attachmentId);
      final url = (answer['ticket'] as Map?)?['downloadUrl'];
      if (url is! String) throw VeilApiException('No download URL.', code: 'attachment_download_invalid');
      return url;
    }

    Future<Uint8List> get(String url) => _api.downloadEncryptedBlob(
          downloadUrl: url,
          maxBytes: cap,
          cancellationSignal: signal,
          onProgress: (received, total) {
            final share = (received / (total ?? cap)).clamp(0.0, 1.0);
            if (share - reported < 0.02 && share < 1) return;
            reported = share;
            onProgress?.call(share);
          },
        );

    String? part;
    try {
      // Fetched right after its ticket, which lives 90 s.
      final url = await ticket();
      Uint8List sealed;
      try {
        sealed = await get(url);
      } on VeilApiException catch (error) {
        // A ticket that ran out, a presign the storage no longer takes.
        final refused = error.code == 'attachment_forbidden' || error.code == 'attachment_not_found';
        if (!refused || signal.isCanceled) rethrow;
        sealed = await get(await ticket());
      }
      if (!stillWanted()) return (path: null, failure: FetchFailure.canceled, error: null);
      part = await _blobs.reservePartPath();
      await File(part).writeAsBytes(sealed, flush: true);
      if (!await digestMatches(part, reference.sha256)) {
        return (path: null, failure: FetchFailure.integrity, error: null);
      }
      if (!stillWanted()) return (path: null, failure: FetchFailure.canceled, error: null);
      final partPath = part;
      final path = await _serial(() => _blobs.commit(
            partPath: partPath,
            conversationId: conversationId,
            attachmentId: reference.attachmentId,
            digest: reference.sha256,
            sizeBytes: sealed.length,
            expiresAt: expiresAt,
          ));
      part = null;
      return (path: path, failure: null, error: null);
    } catch (error) {
      final failure = switch (extractVeilApiErrorCode(error)) {
        'attachment_not_found' || 'attachment_forbidden' => FetchFailure.gone,
        'attachment_download_canceled' => FetchFailure.canceled,
        _ => FetchFailure.failed,
      };
      return (path: null, failure: failure, error: error);
    } finally {
      if (part != null) {
        try {
          await File(part).delete();
        } on FileSystemException {
          // removeOrphans takes anything left.
        }
      }
    }
  }
}

/// At most [capacity] transfers at once, photos fetched by themselves and
/// downloads the user asked for together. Someone waiting for a slot
/// because they tapped goes before anything fetched on its own.
class TransferSlots {
  TransferSlots({this.capacity = 2});

  final int capacity;
  int _busy = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// Whether a slot is free and nobody who tapped is waiting for one.
  bool get hasFreeSlot => _busy < capacity && _waiting.isEmpty;

  int get busy => _busy;

  /// Runs [transfer] once a slot is free.
  Future<T> run<T>(Future<T> Function() transfer) async {
    if (_busy >= capacity || _waiting.isNotEmpty) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _busy += 1;
    }
    try {
      return await transfer();
    } finally {
      if (_waiting.isNotEmpty) {
        // The slot passes straight to who waited longest.
        _waiting.removeFirst().complete();
      } else {
        _busy -= 1;
      }
      onSlotFreed?.call();
    }
  }

  /// Called whenever a transfer ends.
  void Function()? onSlotFreed;
}

/// A photo to fetch by itself: its sealed blob only, digest-checked and
/// kept; nothing is decrypted until the photo is shown.
class PrefetchItem {
  const PrefetchItem({
    required this.key,
    required this.conversationId,
    required this.reference,
    required this.sentAt,
    this.expiresAt,
  });

  final MediaKey key;
  final String conversationId;
  final AttachmentReference reference;

  /// When its message was sent: the newest goes first.
  final DateTime sentAt;

  /// When its message disappears, which its blob is kept until.
  final DateTime? expiresAt;
}

/// Photos waiting to be fetched by themselves (D25): newest first, at most
/// [maxPerConversation] waiting per chat (older ones download when their
/// bubble is built), fetched only while the app is in front and unlocked,
/// in whatever transfer slots are free.
class MediaPrefetch {
  MediaPrefetch({
    required this.slots,
    required Future<void> Function(PrefetchItem item) fetch,
    required bool Function(String conversationId) withheld,
    this.maxPerConversation = 50,
  })  : _fetch = fetch,
        _withheld = withheld {
    slots.onSlotFreed = pump;
  }

  final TransferSlots slots;
  final int maxPerConversation;
  final Future<void> Function(PrefetchItem item) _fetch;
  final bool Function(String conversationId) _withheld;
  final Map<String, List<PrefetchItem>> _queued = {};
  final Set<MediaKey> _inFlight = {};
  bool _running = false;

  /// Whether queued photos are fetched now.
  bool get running => _running;

  bool isQueued(MediaKey key) =>
      _inFlight.contains(key) || (_queued[key.conversationId]?.any((item) => item.key == key) ?? false);

  int get queuedCount => _queued.values.fold(0, (sum, items) => sum + items.length);

  /// Queues [item], unless its chat is withheld or it is queued already.
  /// Returns whether it is queued (or in flight) now.
  bool enqueue(PrefetchItem item) {
    if (_withheld(item.conversationId)) return false;
    if (isQueued(item.key)) return true;
    final items = _queued.putIfAbsent(item.key.conversationId, () => []);
    items
      ..add(item)
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    if (items.length > maxPerConversation) items.removeRange(maxPerConversation, items.length);
    final queued = items.contains(item);
    pump();
    return queued;
  }

  /// Queues the photos among [arrived] (messages of [conversationId] seen
  /// for the first time) that just arrived: opened ([read] answers what
  /// opened), kind image, a pointer [opens] accepts of at most 10 MiB, not
  /// expired by [now], and stored ([stored] answers when) at or after
  /// [since]: content stored earlier is what the cache held, not an arrival.
  Future<void> queueArrivals(
    String conversationId,
    List<ChatMessage> arrived, {
    required Future<DecryptedMessage> Function(ChatMessage message) read,
    required Future<Map<String, MessageContentRecord>> Function(Iterable<ChatMessage> messages) stored,
    required bool Function(AttachmentReference reference) opens,
    required DateTime since,
    required DateTime Function() now,
    required bool Function() stillWanted,
  }) async {
    final photos = <(ChatMessage, AttachmentReference)>[];
    for (final message in arrived) {
      final opened = await read(message).then<DecryptedMessage?>((opened) => opened, onError: (_) => null);
      final reference = opened?.attachment;
      final expiresAt = message.expiresAt;
      if (opened == null || !opened.isOk || opened.messageKind != MessageKind.image || reference == null) continue;
      if (!opens(reference) || reference.sizeBytes > kMaxPhotoBytes) continue;
      if (expiresAt == null || expiresAt.isAfter(now())) photos.add((message, reference));
    }
    if (photos.isEmpty || !stillWanted()) return;
    final records = await stored(photos.map((photo) => photo.$1));
    for (final (message, reference) in photos) {
      final record = records[message.id];
      if (record == null || record.createdAt.isBefore(since) || !stillWanted()) continue;
      enqueue(PrefetchItem(
        key: MediaKey(conversationId, reference),
        conversationId: conversationId,
        reference: reference,
        sentAt: message.sentAt,
        expiresAt: message.expiresAt,
      ));
    }
  }

  void setRunning(bool running) {
    _running = running;
    pump();
  }

  void remove(MediaKey key) {
    _queued[key.conversationId]?.removeWhere((item) => item.key == key);
  }

  void removeWhere(bool Function(MediaKey key) test) {
    for (final items in _queued.values) {
      items.removeWhere((item) => test(item.key));
    }
  }

  void clear() {
    _queued.clear();
    _inFlight.clear();
    _running = false;
  }

  /// Starts the newest queued photos in the free slots.
  void pump() {
    while (_running && slots.hasFreeSlot) {
      final next = _takeNewest();
      if (next == null) return;
      _inFlight.add(next.key);
      unawaited(slots.run(() => _fetch(next)).catchError((Object _) {}).whenComplete(() {
        _inFlight.remove(next.key);
      }));
    }
  }

  PrefetchItem? _takeNewest() {
    PrefetchItem? newest;
    for (final MapEntry(key: conversationId, value: items) in _queued.entries.toList()) {
      // A chat withheld since its photos were queued fetches none of them.
      if (_withheld(conversationId)) {
        _queued.remove(conversationId);
        continue;
      }
      if (items.isEmpty) continue;
      if (newest == null || items.first.sentAt.isAfter(newest.sentAt)) newest = items.first;
    }
    if (newest != null) _queued[newest.key.conversationId]!.remove(newest);
    return newest;
  }
}
