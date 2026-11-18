import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/message_time.dart';
import '../../chat/presentation/photo_image_provider.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../data/attachment_opener.dart';
import '../domain/attachment_rules.dart';
import 'save_media.dart';

/// Shows a photo full screen (D29), over the chat, which stays where it was
/// underneath: a page pushed on the root navigator, not a route of its own.
/// [title] is who sent it as the chat names them ("You" for the user's
/// own); [fileName] is set for a photo that came as a file, which Save
/// keeps. The viewer closes by itself when its message [messageId] leaves
/// the chat or reaches [expiresAt] (a disappearing photo goes with its
/// message), and when the app locks or signs out (nothing decrypted stays
/// on screen or is decoded again behind the lock screen, D36).
Future<void> showPhotoViewer(
  BuildContext context, {
  required String conversationId,
  String? messageId,
  required AttachmentReference attachment,
  required Uint8List bytes,
  required String title,
  required DateTime sentAt,
  DateTime? expiresAt,
  String? fileName,
}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: VeilMotion.fast,
    reverseTransitionDuration: VeilMotion.fast,
    pageBuilder: (context, animation, _) => FadeTransition(
      opacity: animation,
      child: PhotoViewerScreen(
        conversationId: conversationId,
        messageId: messageId,
        attachment: attachment,
        bytes: bytes,
        title: title,
        sentAt: sentAt,
        expiresAt: expiresAt,
        fileName: fileName,
      ),
    ),
  ));
}

/// A photo on black in both themes, as every stock viewer shows one: pinch
/// up to 4x, double tap between 1x and 2.5x, drag down at 1x to close (the
/// photo follows the finger and the black fades), a tap shows or hides the
/// bar. The bar holds the close cross, who sent it and when, and Save. The
/// photo is decoded no larger than the screen can use: its long edge at
/// most twice the screen's, and never past 4096 pixels.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.conversationId,
    this.messageId,
    required this.attachment,
    required this.bytes,
    required this.title,
    required this.sentAt,
    this.expiresAt,
    this.fileName,
  });

  final String conversationId;

  /// The message the photo is in: the viewer closes once it is gone.
  final String? messageId;
  final AttachmentReference attachment;
  final Uint8List bytes;
  final String title;
  final DateTime sentAt;
  final DateTime? expiresAt;
  final String? fileName;

  /// The scale a double tap zooms to.
  static const double doubleTapScale = 2.5;
  static const double maxScale = 4;

  /// How far a drag down at 1x must go to close the viewer.
  static const double closeDistance = 120;

  /// The black of the flat band behind the bars while they show: white on
  /// it reads at 6:1 even over a white photo.
  static const double barBandOpacity = 0.65;

  /// The long edge the photo is decoded at on a screen whose long edge is
  /// [screenLongEdge] physical pixels.
  static int decodeEdge(double screenLongEdge) => math.min(kViewerMaxEdge, (2 * screenLongEdge).round());

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> with TickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoom = AnimationController(vsync: this, duration: VeilMotion.fast);
  late final AnimationController _settle = AnimationController(vsync: this, duration: VeilMotion.fast);
  Animation<Matrix4>? _zoomTo;
  Animation<double>? _dragBack;
  bool _barsShown = true;
  bool _atRest = true;
  double _drag = 0;
  Offset? _doubleTapAt;
  Timer? _expiry;
  bool _closing = false;

  // The media service and its eviction count when the viewer opened: once
  // they differ, the app locked or signed out.
  late final AttachmentMediaService _media;
  late final int _evictions;
  bool _evicted = false;

  @override
  void initState() {
    super.initState();
    _media = ref.read(messengerControllerProvider).media;
    _evictions = _media.evictions;
    _media.addListener(_onMedia);
    // A disappearing photo goes with its message (D37): the viewer closes
    // when the message leaves the chat or its time runs out.
    ref.listenManual(messengerControllerProvider, (_, __) => scheduleMicrotask(_closeIfGone));
    final expiresAt = widget.expiresAt;
    if (expiresAt != null) {
      final left = expiresAt.difference(ref.read(messengerControllerProvider).expiryNow());
      _expiry = Timer(left.isNegative ? Duration.zero : left + const Duration(milliseconds: 1), _closeIfGone);
    }
    _transform.addListener(() {
      final atRest = _transform.value.getMaxScaleOnAxis() <= 1.01;
      if (atRest != _atRest) setState(() => _atRest = atRest);
    });
    _zoom.addListener(() {
      if (_zoomTo case final zoomTo?) _transform.value = zoomTo.value;
    });
    _settle.addListener(() {
      if (_dragBack case final back?) setState(() => _drag = back.value);
    });
  }

  // The app locked or signed out: the decrypted photo leaves the screen at
  // once, so nothing decodes it again into the emptied image cache while
  // the router takes the viewer down. Should the viewer still be up a frame
  // later, it closes.
  void _onMedia() {
    if (_evicted || _media.evictions == _evictions || !mounted) return;
    setState(() => _evicted = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  // The message is gone or expired: the viewer, and a Save dialog over it,
  // close.
  void _closeIfGone() {
    if (!mounted || _closing) return;
    final controller = ref.read(messengerControllerProvider);
    final expiresAt = widget.expiresAt;
    final messageId = widget.messageId;
    final expired = expiresAt != null && !expiresAt.isAfter(controller.expiryNow());
    final left = messageId != null && !controller.messagesFor(widget.conversationId).any((m) => m.id == messageId);
    if (expired || left) _close();
  }

  void _close() {
    if (!mounted || _closing) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    _closing = true;
    Navigator.of(context)
      ..popUntil((candidate) => candidate == route)
      ..pop();
  }

  @override
  void dispose() {
    _media.removeListener(_onMedia);
    _expiry?.cancel();
    _zoom.dispose();
    _settle.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final size = MediaQuery.sizeOf(context);
    final at = _doubleTapAt ?? size.center(Offset.zero);
    const scale = PhotoViewerScreen.doubleTapScale;
    final target = _atRest
        ? (Matrix4.identity()
          ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
          ..scaleByDouble(scale, scale, 1, 1))
        : Matrix4.identity();
    _zoomTo = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _zoom, curve: VeilMotion.emphasize));
    _zoom.forward(from: 0);
  }

  void _dragEnded(DragEndDetails details) {
    if (_drag.abs() > PhotoViewerScreen.closeDistance || details.primaryVelocity!.abs() > 900) {
      Navigator.of(context).pop();
      return;
    }
    _dragBack =
        Tween<double>(begin: _drag, end: 0).animate(CurvedAnimation(parent: _settle, curve: VeilMotion.emphasize));
    _settle.forward(from: 0);
  }

  Future<void> _save() => saveAttachment(
        context,
        ref,
        conversationId: widget.conversationId,
        attachment: widget.attachment,
        name: widget.fileName ?? photoFileName(widget.sentAt),
        photo: widget.fileName == null,
        expiresAt: widget.expiresAt,
      );

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(messengerControllerProvider.select((controller) => controller.media));
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final key = MediaKey(widget.conversationId, widget.attachment);
    // Checked here too, not only when told: a rebuild after a lock never
    // draws the photo again.
    final evicted = _evicted || !identical(media, _media) || media.evictions != _evictions;
    final provider = evicted
        ? null
        : PhotoImageProvider(
            media: key,
            bytes: widget.bytes,
            target: PhotoDecodeTarget.viewer(PhotoViewerScreen.decodeEdge(math.max(size.width, size.height) * ratio)),
          );
    if (provider != null) media.noteImageKey(key, provider.key);
    final fade = (1 - _drag.abs() / 400).clamp(0.0, 1.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: fade))),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _barsShown = !_barsShown),
                onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
                onDoubleTap: _toggleZoom,
                onVerticalDragUpdate: _atRest ? (details) => setState(() => _drag += details.delta.dy) : null,
                onVerticalDragEnd: _atRest ? _dragEnded : null,
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: InteractiveViewer(
                    key: const ValueKey('photo-viewer-zoom'),
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: PhotoViewerScreen.maxScale,
                    panEnabled: !_atRest,
                    child: SizedBox.expand(
                      child: provider == null
                          ? null
                          : Image(
                              image: provider,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (context, _, __) => const SizedBox.shrink(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            _Bar(
              shown: _barsShown && _drag == 0,
              title: widget.title,
              subtitle: _when(context),
              onClose: () => Navigator.of(context).pop(),
              // No save screen on this platform: no Save.
              onSave: ref.read(fileHandOverAvailableProvider) ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  // "Today at 9:52 AM", "Yesterday at…", "Apr 2 at…".
  String _when(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = MessageTimeFormat.of(context);
    final sent = widget.sentAt.toLocal();
    final now = ref.read(wallClockProvider)().toLocal();
    final day = switch (calendarDaysBetween(sent, now)) {
      <= 0 => l10n.chatDayToday,
      1 => l10n.chatDayYesterday,
      _ when sent.year == now.year => DateFormat.MMMd(l10n.localeName).format(sent),
      _ => DateFormat.yMMMd(l10n.localeName).format(sent),
    };
    return l10n.dayAtTime(day, format.timeOfDay(sent));
  }
}

/// The viewer's bar: 52 dp, in white whatever the app's theme, on a flat
/// band of [PhotoViewerScreen.barBandOpacity] black that runs up behind the
/// status bar, so it reads over a photo that reaches under it (a tall photo
/// or a screenshot) as well as over the black.
class _Bar extends StatelessWidget {
  static const VeilPalette _ink = VeilPalette.dark;

  /// The day and time under the name: white, a little dimmer than the name,
  /// which still reads at 4.5:1 on the band over a white photo.
  static final Color _subtitleInk = _ink.text.withValues(alpha: 0.85);

  const _Bar({
    required this.shown,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onSave,
  });

  final bool shown;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: VeilMotion.fast,
          child: ColoredBox(
            key: const ValueKey('photo-viewer-bar-band'),
            color: Colors.black.withValues(alpha: PhotoViewerScreen.barBandOpacity),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onClose,
                      tooltip: l10n.commonClose,
                      icon: Icon(Icons.close, color: _ink.text),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(color: _ink.text),
                            ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: _subtitleInk),
                          ),
                        ],
                      ),
                    ),
                    if (onSave != null)
                      IconButton(
                        key: const ValueKey('photo-viewer-save'),
                        onPressed: onSave,
                        tooltip: l10n.chatSaveAction,
                        icon: Icon(Icons.download_outlined, color: _ink.text),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
