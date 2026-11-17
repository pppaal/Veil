import 'package:flutter/foundation.dart';

import '../../../../core/network/veil_api_client.dart';
import '../../../attachments/data/attachment_storage_paths.dart';
import '../../../attachments/data/media_blob_store.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

/// Photos and files in messages: prefetch, download, decrypt, keep sealed,
/// open.
///
/// For now it holds the sealed media store and the rules it will go by,
/// and does nothing else: no photo is fetched or opened yet.
/// MessengerServices.dispose disposes it with the messenger, so whatever
/// it runs (timers, transfers) stops in its [dispose].
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
  });

  /// Sealed blobs on the phone, under random names.
  final MediaBlobStore blobs;

  /// Whether nothing in [conversationId] may be fetched on its own: who its
  /// peer is waits for the user, or it is a 1:1 with someone blocked
  /// (MessengerServices.autoDownloadWithheld).
  final bool Function(String conversationId) autoDownloadWithheld;

  /// The attachment ids of uploads still pending, whose blobs no cleanup
  /// may take (OutboxService.pendingAttachmentIds).
  final Set<String> Function() pendingAttachmentIds;

  /// Drops every decrypted byte held in memory, and every Save copy: the
  /// session locked.
  void evictDecrypted() {}

  /// Whether the app is in front and unlocked (the app sets it through
  /// [setInUse]); media work runs only then.
  bool get inUse => _inUse;
  bool _inUse = false;

  /// Whether the app is in front and unlocked; media work runs only then.
  void setInUse(bool inUse) => _inUse = inUse;

  /// Forgets everything held for the identity that left.
  void clear() {}

  @override
  void conversationsChanged() {}

  @override
  void messagesChanged(String conversationId) {}

  @override
  void pagingChanged(String conversationId) {}
}
