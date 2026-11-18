import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/presentation/photo_viewer_screen.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';
import 'photo_image_provider.dart';

/// A photo message: the photo is the bubble (D23), at its own aspect within
/// 150 to 240 dp by 100 to 320 dp, a group's sender in a strip above it and
/// the meta in a strip of the bubble's fill under it. Before it opens, a
/// 210 dp square tile says where it stands (D24, D31): a ring while it
/// downloads, the download glyph when a tap fetches it, why it is not
/// there when it is gone, with the size under the glyph. The user's own
/// photo shows from the sealed blob on this phone, under a scrim with the
/// upload ring and a cross while it sends (D26). A tap opens the viewer.
/// Bytes this version cannot show turn the bubble into [unsupported].
class MessagePhoto extends ConsumerStatefulWidget {
  const MessagePhoto({
    super.key,
    required this.conversationId,
    required this.message,
    required this.attachment,
    required this.meta,
    required this.unsupported,
    this.position = VeilBubblePosition.single,
    this.highlighted = false,
    this.senderName,
    this.senderSeed,
    this.authorName,
    this.transferSnapshot,
    this.onCancelAttachment,
  });

  final String conversationId;
  final ChatMessage message;
  final AttachmentReference attachment;

  /// The time, timer and status glyph, drawn in the strip under the photo.
  final Widget meta;

  /// What the message shows when its bytes are not a photo this version
  /// draws: the card that says it cannot open it.
  final Widget unsupported;
  final VeilBubblePosition position;
  final bool highlighted;
  final String? senderName;
  final String? senderSeed;

  /// Who sent it as the chat names them; null on the user's own.
  final String? authorName;
  final AttachmentTransferSnapshot? transferSnapshot;
  final VoidCallback? onCancelAttachment;

  /// The meta strip under the photo.
  static const double metaStripHeight = 24;

  @override
  ConsumerState<MessagePhoto> createState() => _MessagePhotoState();
}

class _MessagePhotoState extends ConsumerState<MessagePhoto> {
  Uint8List? _bytes;
  int _evictions = 0;
  bool _asking = false;
  (MediaState, bool)? _askedAt;
  PhotoImageKey? _resolving;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: _onImageError);
  ImageInfo? _image;
  bool _undrawable = false;

  // The size it was shown at, kept across a lock so it comes back in place.
  Size? _photoSize;
  bool _grew = false;

  MediaKey get _key => MediaKey(widget.conversationId, widget.attachment);

  @override
  void didUpdateWidget(MessagePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaKey(oldWidget.conversationId, oldWidget.attachment) != _key) {
      _drop();
      _photoSize = null;
      _undrawable = false;
      _askedAt = null;
    }
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    _stream?.removeListener(_listener);
    _stream = null;
    _resolving = null;
    _image?.dispose();
    _image = null;
    _bytes = null;
  }

  void _onImage(ImageInfo image, bool synchronousCall) {
    void take() {
      _image?.dispose();
      _image = image;
      _photoSize = Size(image.image.width.toDouble(), image.image.height.toDouble());
    }

    if (synchronousCall || !mounted) return take();
    setState(take);
  }

  void _onImageError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    setState(() => _undrawable = true);
  }

  // Asks the media service for the photo once per state it is in.
  void _ask(AttachmentMediaService media, MediaStatus status, {bool userAsked = false}) {
    final at = (status.state, media.inUse);
    if (_asking || (!userAsked && _askedAt == at)) return;
    _asking = true;
    _askedAt = at;
    final evictions = media.evictions;
    scheduleMicrotask(() async {
      final bytes = await media.photoBytes(widget.conversationId, widget.attachment,
          userAsked: userAsked, expiresAt: widget.message.expiresAt, sentAt: widget.message.sentAt);
      _asking = false;
      if (!mounted || bytes == null || media.evictions != evictions) return;
      setState(() {
        _bytes = bytes;
        _grew = _photoSize == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(messengerControllerProvider.select((controller) => controller.media));
    return ListenableBuilder(listenable: media, builder: (context, _) => _build(context, media));
  }

  Widget _build(BuildContext context, AttachmentMediaService media) {
    if (media.evictions != _evictions) {
      // The app locked: the decoded photo goes too.
      _evictions = media.evictions;
      _drop();
      _askedAt = null;
    }
    final status = media.statusOf(widget.conversationId, widget.attachment);
    if (status.state == MediaState.unsupported || _undrawable) return widget.unsupported;
    _bytes ??= media.cachedPhotoBytes(widget.conversationId, widget.attachment);
    if (_bytes == null) _ask(media, status);

    final l10n = AppLocalizations.of(context);
    final own = widget.message.isMine && !widget.highlighted;
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
      final maxWidth = math.min(240.0, available * VeilBubble.widthShare);
      if (_bytes case final bytes?) _resolve(context, media, bytes, maxWidth);
      final photo = _photoSize;
      final size = photo == null
          ? Size.square(math.min(photoTileExtent, maxWidth))
          : photoBubbleSize(photo.width.round(), photo.height.round(), maxWidth: maxWidth);
      final failed = widget.message.hasFailed;
      final opened = _image != null;
      final canOpen = opened && !_sending && !failed;
      final canFetch = !opened && (status.state == MediaState.idle || status.state == MediaState.failed);
      final body = AnimatedContainer(
        duration: _grew ? VeilMotion.fast : Duration.zero,
        width: size.width,
        height: size.height,
        child: Stack(fit: StackFit.expand, children: [
          if (_image case final image?)
            RawImage(image: image.image, fit: BoxFit.cover, alignment: Alignment.center)
          else
            _Tile(status: status, sizeBytes: widget.attachment.sizeBytes, own: own, opening: _bytes != null),
          if (widget.message.isMine) ..._sendState(l10n),
        ]),
      );
      return Semantics(
        label: l10n.chatAttachmentKindPhoto,
        button: canOpen || canFetch,
        onTapHint: canOpen ? l10n.chatOpenAction : (canFetch ? l10n.chatDownloadAction : null),
        child: VeilBubble(
          isMine: widget.message.isMine,
          highlighted: widget.highlighted,
          position: widget.position,
          failed: failed,
          failedText: failed ? l10n.chatNotSentTapToRetry : null,
          flush: true,
          child: SizedBox(
            width: size.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.senderName case final name?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(VeilSpace.sm, 6, VeilSpace.sm, 4),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: VeilAvatar.nameTint(context, widget.senderSeed ?? name),
                          ),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canOpen
                      ? () => _openViewer(context, media)
                      : canFetch
                          ? () {
                              VeilHaptics.light();
                              _ask(media, status, userAsked: true);
                            }
                          : null,
                  child: body,
                ),
                SizedBox(
                  height: MessagePhoto.metaStripHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm),
                    child: Align(alignment: AlignmentDirectional.centerEnd, child: widget.meta),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  bool get _sending {
    final snapshot = widget.transferSnapshot;
    return widget.message.isMine &&
        snapshot != null &&
        !widget.message.hasFailed &&
        snapshot.phase != AttachmentTransferPhase.failed &&
        snapshot.phase != AttachmentTransferPhase.canceled;
  }

  // While the user's own photo sends: a scrim, the white upload ring and a
  // cross that cancels it. A failed one keeps the cross, with no scrim.
  List<Widget> _sendState(AppLocalizations l10n) {
    final snapshot = widget.transferSnapshot;
    final cancel = snapshot != null && snapshot.canCancel ? widget.onCancelAttachment : null;
    final sending = _sending;
    if (!sending && cancel == null) return const [];
    final uploading = snapshot?.phase == AttachmentTransferPhase.uploading;
    return [
      if (sending) const ColoredBox(color: Color(0x66000000)),
      Center(
        child: SizedBox.square(
          dimension: 44,
          child: Stack(alignment: Alignment.center, children: [
            if (!sending) const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
              child: SizedBox.square(dimension: 40),
            ),
            if (sending)
              Semantics(
                label: l10n.chatDeliveryUploading,
                child: SizedBox.square(
                  dimension: 40,
                  child: CircularProgressIndicator(
                    value: uploading ? snapshot!.progress.clamp(0.0, 1.0) : null,
                    strokeWidth: 3,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            if (cancel != null)
              IconButton(
                onPressed: cancel,
                tooltip: l10n.chatCancelAction,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, size: 20, color: Colors.white),
              ),
          ]),
        ),
      ),
    ];
  }

  void _resolve(BuildContext context, AttachmentMediaService media, Uint8List bytes, double maxWidth) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final provider = PhotoImageProvider(
      media: _key,
      bytes: bytes,
      target: PhotoDecodeTarget.bubble((maxWidth * ratio).round()),
    );
    if (provider.key == _resolving) return;
    _resolving = provider.key;
    media.noteImageKey(_key, provider.key);
    _stream?.removeListener(_listener);
    _stream = provider.resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  void _openViewer(BuildContext context, AttachmentMediaService media) {
    final bytes = _bytes;
    if (bytes == null) return;
    VeilHaptics.light();
    final l10n = AppLocalizations.of(context);
    unawaited(showPhotoViewer(
      context,
      conversationId: widget.conversationId,
      attachment: widget.attachment,
      bytes: bytes,
      title: widget.message.isMine ? l10n.viewerSenderYou : (widget.authorName ?? ''),
      sentAt: widget.message.sentAt,
      expiresAt: widget.message.expiresAt,
    ));
  }
}

/// The square an incoming photo shows until it opens.
class _Tile extends StatelessWidget {
  const _Tile({required this.status, required this.sizeBytes, required this.own, required this.opening});

  final MediaStatus status;
  final int sizeBytes;
  final bool own;

  /// Its bytes are here and being drawn: nothing to say meanwhile.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final muted = own ? palette.outgoingMeta : palette.textMuted;
    final line = theme.textTheme.bodySmall?.copyWith(color: muted);
    if (opening || status.state == MediaState.ready) return const SizedBox.expand();
    final (Widget glyph, String caption) = switch (status.state) {
      MediaState.downloading => (
          Semantics(
            label: l10n.chatDownloading,
            child: SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(
                value: status.progress,
                strokeWidth: 3,
                color: own ? Colors.white : palette.primaryStrong,
                backgroundColor: own ? Colors.white24 : palette.stroke,
              ),
            ),
          ),
          formatFileSize(sizeBytes),
        ),
      MediaState.gone => (
          Icon(Icons.hide_image_outlined,
              size: VeilIconSize.lg, color: own ? palette.outgoingMeta : palette.textSubtle),
          l10n.chatPhotoUnavailable,
        ),
      MediaState.failed => (_DownloadGlyph(own: own), l10n.chatDownloadFailed),
      _ => (_DownloadGlyph(own: own), formatFileSize(sizeBytes)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          glyph,
          const SizedBox(height: VeilSpace.xs),
          Text(caption, style: line, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// The download glyph in its 40 dp circle.
class _DownloadGlyph extends StatelessWidget {
  const _DownloadGlyph({required this.own});

  final bool own;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return DecoratedBox(
      decoration: BoxDecoration(color: own ? Colors.white24 : palette.surfaceRaised, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(Icons.download_outlined, size: 24, color: own ? Colors.white : palette.text),
      ),
    );
  }
}
