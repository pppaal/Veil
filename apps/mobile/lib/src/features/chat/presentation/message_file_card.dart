import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/data/attachment_decrypt.dart' show readImageHeader;
import '../../attachments/data/attachment_opener.dart';
import '../../attachments/domain/attachment_rules.dart';
import '../../attachments/presentation/photo_viewer_screen.dart';
import '../../attachments/presentation/save_media.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// A file in a message (D27): a 40 dp circle holding where it stands (the
/// download glyph, a ring with a cross while it downloads or sends, the
/// file glyph once it is here), the sender's file name on one line, cut in
/// the middle so its real extension stays, and "PDF · 2.3 MB" under it, the
/// type from that extension, never from what the sender claims. A tap
/// fetches it, or opens it (D28): in the viewer when it is a photo this
/// version draws, else in another app.
class MessageFileCard extends ConsumerStatefulWidget {
  const MessageFileCard({
    super.key,
    required this.conversationId,
    required this.message,
    required this.attachment,
    required this.name,
    this.authorName,
    this.transferSnapshot,
    this.onCancelAttachment,
  });

  final String conversationId;
  final ChatMessage message;
  final AttachmentReference attachment;

  /// The file's name as the sender wrote it; sanitized here.
  final String name;
  final String? authorName;
  final AttachmentTransferSnapshot? transferSnapshot;
  final VoidCallback? onCancelAttachment;

  @override
  ConsumerState<MessageFileCard> createState() => _MessageFileCardState();
}

class _MessageFileCardState extends ConsumerState<MessageFileCard> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // A file sent from here, or fetched before, is ready without a fetch.
    unawaited(ref.read(messengerControllerProvider).media.refresh(widget.conversationId, widget.attachment));
  }

  bool get _sending {
    final snapshot = widget.transferSnapshot;
    return widget.message.isMine &&
        snapshot != null &&
        !widget.message.hasFailed &&
        snapshot.phase != AttachmentTransferPhase.failed &&
        snapshot.phase != AttachmentTransferPhase.canceled;
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(messengerControllerProvider.select((controller) => controller.media));
    return ListenableBuilder(listenable: media, builder: (context, _) => _build(context, media));
  }

  Widget _build(BuildContext context, AttachmentMediaService media) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final own = widget.message.isMine;
    final status = media.statusOf(widget.conversationId, widget.attachment);
    final name = sanitizeFileName(widget.name, fallback: l10n.chatAttachmentKindFile);
    final type = fileTypeLabel(name) ?? l10n.chatAttachmentKindFile;
    final typeSize = l10n.chatAttachmentTypeSize(type, formatFileSize(widget.attachment.sizeBytes));
    final sending = _sending;
    final snapshot = widget.transferSnapshot;
    final downloading = status.state == MediaState.downloading;
    // A send that failed is retried by a tap on its bubble, not opened.
    final ready = !sending && !widget.message.hasFailed && (own || status.state == MediaState.ready);
    final canFetch =
        !own && !ready && (status.state == MediaState.idle || status.state == MediaState.failed);
    final muted = theme.textTheme.bodySmall?.copyWith(color: own ? palette.outgoingMeta : palette.textMuted);
    final note = switch (status.state) {
      _ when sending || ready => null,
      MediaState.failed => l10n.chatDownloadFailed,
      MediaState.gone => l10n.chatFileUnavailable,
      _ => null,
    };
    final VoidCallback? cancel = sending
        ? (snapshot!.canCancel ? widget.onCancelAttachment : null)
        : downloading
            ? () => media.cancel(widget.conversationId, widget.attachment)
            : null;
    final ringValue = sending
        ? (snapshot!.phase == AttachmentTransferPhase.uploading ? snapshot.progress.clamp(0.0, 1.0) : null)
        : status.progress;
    final circle = _Circle(
      own: own,
      child: sending || downloading
          ? Stack(alignment: Alignment.center, children: [
              Semantics(
                label: sending ? l10n.chatDeliveryUploading : l10n.chatDownloading,
                child: SizedBox.square(
                  dimension: 36,
                  child: CircularProgressIndicator(
                    value: ringValue,
                    strokeWidth: 2.5,
                    color: own ? Colors.white : palette.primaryStrong,
                    backgroundColor: own ? Colors.white24 : palette.stroke,
                  ),
                ),
              ),
              if (cancel != null)
                IconButton(
                  onPressed: cancel,
                  tooltip: sending ? l10n.chatCancelAction : l10n.chatCancelDownload,
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close, size: 18, color: own ? Colors.white : palette.text),
                ),
            ])
          : Icon(
              ready || status.state == MediaState.gone ? Icons.insert_drive_file_outlined : Icons.download_outlined,
              size: VeilIconSize.md,
              color: status.state == MediaState.gone && !ready
                  ? palette.textSubtle
                  : (own ? Colors.white : palette.text),
            ),
    );
    final onTap = ready && !_opening
        ? () => _open(context)
        : canFetch
            ? () {
                VeilHaptics.light();
                unawaited(media.download(widget.conversationId, widget.attachment,
                    expiresAt: widget.message.expiresAt));
              }
            : null;
    return Semantics(
      label: '$name, $typeSize',
      button: onTap != null,
      onTapHint: ready ? l10n.chatOpenAction : (canFetch ? l10n.chatDownloadAction : null),
      excludeSemantics: cancel == null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              circle,
              const SizedBox(width: VeilSpace.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MiddleEllipsisText(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(color: own ? Colors.white : palette.text),
                    ),
                    Text(typeSize, style: muted, maxLines: 1),
                    if (note != null) Text(note, style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    setState(() => _opening = true);
    try {
      await openFileAttachment(
        context,
        ref,
        conversationId: widget.conversationId,
        message: widget.message,
        attachment: widget.attachment,
        name: sanitizeFileName(widget.name),
        authorName: widget.authorName,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

/// Opens a received or sent file (D28): decrypted into its own folder
/// under veil_open, then shown in the viewer when its bytes are a JPEG,
/// PNG or WebP within the render limits; on iOS an image or a video the
/// viewer cannot show goes to Save instead (Quick Look would offer to save
/// it to Photos, which the app has no permission for); anything else opens
/// in another app as the type its extension names.
Future<void> openFileAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required ChatMessage message,
  required AttachmentReference attachment,
  required String name,
  String? authorName,
}) async {
  final l10n = AppLocalizations.of(context);
  final media = ref.read(messengerControllerProvider).media;
  final opener = ref.read(attachmentOpenerProvider);
  final path = await media.plaintextFileFor(conversationId, attachment,
      name: name, purpose: MediaCopyPurpose.open, expiresAt: message.expiresAt);
  if (path == null) {
    final state = media.statusOf(conversationId, attachment).state;
    // A failed or gone fetch says so on the card itself.
    if (context.mounted && state != MediaState.failed && state != MediaState.gone) {
      showVeilToast(context, l10n.chatOpenFileFailed);
    }
    return;
  }
  final bytes = await File(path).readAsBytes();
  final head = bytes.length > 64 ? bytes.sublist(0, 64) : bytes;
  final type = sniffImageType(head);
  final header = type == null ? null : await readImageHeader(bytes);
  if (type != null && header != null && withinRenderLimits(type, header.width, header.height)) {
    await media.releaseCopy(path);
    if (!context.mounted) return;
    await showPhotoViewer(
      context,
      conversationId: conversationId,
      attachment: attachment,
      bytes: bytes,
      title: message.isMine ? l10n.viewerSenderYou : (authorName ?? ''),
      sentAt: message.sentAt,
      expiresAt: message.expiresAt,
      fileName: name,
    );
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS && isImageOrVideoForQuickLook(head, name)) {
    await media.releaseCopy(path);
    if (!context.mounted) return;
    await saveAttachment(context, ref,
        conversationId: conversationId, attachment: attachment, name: name, expiresAt: message.expiresAt);
    return;
  }
  final outcome = await opener.open(path, mimeType: contentTypeForName(name));
  // On Android the other app may still be reading it: the copy goes with
  // the sweep, its message's expiry, or the next start.
  if (outcome != OpenOutcome.opened) await media.releaseCopy(path);
  if (!context.mounted) return;
  if (outcome == OpenOutcome.noApp) showVeilToast(context, l10n.chatOpenFileNoApp);
  if (outcome == OpenOutcome.failed) showVeilToast(context, l10n.chatOpenFileFailed);
}

class _Circle extends StatelessWidget {
  const _Circle({required this.own, required this.child});

  final bool own;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: own ? Colors.white.withValues(alpha: 0.2) : context.veilPalette.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 40, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// One line of [text], cut in the middle when it does not fit, keeping its
/// end (a file's real extension and a few characters before it):
/// "Lease agreement…final.pdf". It reports its sizes to the bubble, which
/// is as wide as its widest line.
class MiddleEllipsisText extends LeafRenderObjectWidget {
  const MiddleEllipsisText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMiddleEllipsisText(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderMiddleEllipsisText renderObject) {
    renderObject.update(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}

class RenderMiddleEllipsisText extends RenderBox {
  RenderMiddleEllipsisText({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
  })  : _text = text,
        _style = style,
        _painter = TextPainter(textDirection: textDirection, textScaler: textScaler, maxLines: 1);

  String _text;
  TextStyle _style;
  final TextPainter _painter;
  String _shown = '';

  void update({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    if (text == _text &&
        style == _style &&
        textDirection == _painter.textDirection &&
        textScaler == _painter.textScaler) {
      return;
    }
    _text = text;
    _style = style;
    _painter
      ..textDirection = textDirection
      ..textScaler = textScaler;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  // The end kept: the extension and up to six characters before it.
  String get _tail {
    final characters = _text.characters.toList();
    if (characters.length < 2) return _text;
    final extension = fileExtension(_text);
    final length = (extension.isEmpty ? 6 : extension.length + 7).clamp(1, characters.length - 1);
    return characters.sublist(characters.length - length).join();
  }

  Size _measure(String text) {
    _painter
      ..text = TextSpan(text: text, style: _style)
      ..layout();
    return _painter.size;
  }

  String _fit(double width) {
    if (_measure(_text).width <= width) return _text;
    final characters = _text.characters.toList();
    final tail = _tail;
    final tailLength = tail.characters.length;
    String cut(int keep) => '${characters.take(keep).join().trimRight()}…$tail';
    var low = 0;
    var high = characters.length - tailLength;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_measure(cut(mid)).width <= width) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return cut(low);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _measure('…$_tail').width;

  @override
  double computeMaxIntrinsicWidth(double height) => _measure(_text).width;

  @override
  double computeMinIntrinsicHeight(double width) => _measure(_text).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _measure(_text).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_measure(constraints.hasBoundedWidth ? _fit(constraints.maxWidth) : _text));

  @override
  void performLayout() {
    _shown = constraints.hasBoundedWidth ? _fit(constraints.maxWidth) : _text;
    size = constraints.constrain(_measure(_shown));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _measure(_shown);
    _painter.paint(context.canvas, offset);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _painter.textDirection;
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

