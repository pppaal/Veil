import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/send_button.dart';
import '../data/image_preparer.dart';

/// How the photo preview closed: Send, the close cross, or the photo could
/// not be prepared. A preview the lock takes down closes with none.
enum PhotoSendChoice { send, close, failed }

/// The photo about to be sent, on black as the viewer shows photos: the
/// close cross at the top, the photo whole in between, and the send circle
/// at the bottom end. No caption, no editing (D11, D12): what is typed in
/// the composer stays there. The photo is being prepared while this shows;
/// Send waits for it.
class PhotoSendScreen extends StatefulWidget {
  const PhotoSendScreen({super.key, required this.prepared});

  /// The photo as it will be sent; null when it cannot be prepared.
  final Future<PreparedImage?> prepared;

  /// The preview as a page over the chat (not a route of its own).
  static Route<PhotoSendChoice> route(Future<PreparedImage?> prepared) => MaterialPageRoute<PhotoSendChoice>(
        fullscreenDialog: true,
        builder: (_) => PhotoSendScreen(prepared: prepared),
      );

  /// The bars above and below the photo.
  static const double barHeight = 52;

  /// The strip under the photo that holds the 48dp send circle.
  static const double sendBarHeight = 72;

  @override
  State<PhotoSendScreen> createState() => _PhotoSendScreenState();
}

class _PhotoSendScreenState extends State<PhotoSendScreen> {
  MemoryImage? _photo;
  bool _sendWhenReady = false;

  @override
  void initState() {
    super.initState();
    widget.prepared.then((photo) {
      if (!mounted) return;
      if (photo == null) {
        Navigator.of(context).pop(PhotoSendChoice.failed);
        return;
      }
      setState(() => _photo = MemoryImage(photo.bytes));
      if (_sendWhenReady) Navigator.of(context).pop(PhotoSendChoice.send);
    });
  }

  @override
  void dispose() {
    // The decoded pixels leave the image cache with the preview, also when
    // the lock takes it down.
    _photo?.evict().ignore();
    super.dispose();
  }

  void _send() {
    if (_photo == null) {
      setState(() => _sendWhenReady = true);
      return;
    }
    Navigator.of(context).pop(PhotoSendChoice.send);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photo = _photo;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: PhotoSendScreen.barHeight,
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('photo-send-close'),
                      tooltip: l10n.commonClose,
                      onPressed: () => Navigator.of(context).pop(PhotoSendChoice.close),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: photo == null
                      ? const SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Image(
                          image: photo,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          semanticLabel: l10n.chatAttachmentKindPhoto,
                        ),
                ),
              ),
              SizedBox(
                height: PhotoSendScreen.sendBarHeight,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: VeilSpace.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SendButton(
                      key: const ValueKey('photo-send-send'),
                      onPressed: _sendWhenReady ? () {} : _send,
                      semanticLabel: l10n.chatSendAction,
                      large: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
