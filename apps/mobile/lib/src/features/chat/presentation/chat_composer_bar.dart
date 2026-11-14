import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'chat_room_labels.dart';
import 'gradient_send_button.dart';

/// The composer at the foot of a chat: the draft, the line saying whether
/// what is sent disappears, and the send button. Typing tells the peer. A
/// send the messenger holds back for an identity change or a held account
/// keeps the draft for after the review.
class ChatComposerBar extends ConsumerStatefulWidget {
  const ChatComposerBar({
    super.key,
    required this.conversationId,
    required this.focusNode,
    required this.messageTtl,
    required this.busy,
  });

  final String conversationId;

  /// Owned by the screen, which focuses the composer from elsewhere too.
  final FocusNode focusNode;

  /// How long what is sent now lasts; null when it does not disappear.
  final Duration? messageTtl;

  /// Whether the messenger is busy, which disables sending.
  final bool busy;

  @override
  ConsumerState<ChatComposerBar> createState() => _ChatComposerBarState();
}

class _ChatComposerBarState extends ConsumerState<ChatComposerBar> {
  final _messageController = TextEditingController();
  double _sendScale = 1.0;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleComposerChanged);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (_messageController.text.trim().isNotEmpty) {
      ref.read(messengerControllerProvider).notifyTyping(widget.conversationId);
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }

    setState(() => _sendScale = 0.85);
    Future<void>.delayed(VeilMotion.fast, () {
      if (mounted) setState(() => _sendScale = 1.0);
    });

    final controller = ref.read(messengerControllerProvider);
    await controller.sendText(
      conversationId: widget.conversationId,
      body: body,
      disappearAfter: widget.messageTtl,
    );
    // Held back by an identity change or a held account: the text stays for
    // after the review.
    if (controller.pendingIdentityChangeFor(widget.conversationId) == null &&
        controller.peerAccountHoldFor(widget.conversationId) == null) {
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messageTtl = widget.messageTtl;
    return VeilComposer(
      controller: _messageController,
      focusNode: widget.focusNode,
      enabled: !widget.busy,
      onSubmit: _sendMessage,
      helper: messageTtl == null
          ? l10n.chatComposerExpiryOff
          : l10n.chatComposerExpiryOn(formatDurationLabel(l10n, messageTtl)),
      trailing: AnimatedScale(
        scale: _sendScale,
        duration: VeilMotion.fast,
        curve: VeilMotion.emphasize,
        child: GradientSendButton(
          onPressed: widget.busy ? null : _sendMessage,
          busy: widget.busy,
        ),
      ),
    );
  }
}
