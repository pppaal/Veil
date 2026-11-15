import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../../shared/presentation/veil_unavailable.dart';
import '../../conversations/data/messenger/attachment_transfer_service.dart' show AttachmentTransferService;

/// Sends an attachment into a conversation. This build has no file picker,
/// so what it sends is a placeholder: 2 KB of random bytes, sealed, ticketed
/// and uploaded the way a chosen file will be. The screen says exactly that,
/// takes the name the placeholder goes under, and sends.
///
/// The name never leaves this device. Its ending decides the type written
/// into the sealed message, which is what the recipient is shown.
class AttachmentPreviewScreen extends ConsumerStatefulWidget {
  const AttachmentPreviewScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<AttachmentPreviewScreen> createState() => _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends ConsumerState<AttachmentPreviewScreen> {
  final _filenameController = TextEditingController(text: 'dossier.enc');

  // Whether the last send from this screen failed. The messenger has one
  // error line for everything it does, so the line alone does not say that
  // a send from here went wrong: it may be left from before the screen
  // opened.
  bool _sendFailed = false;

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ref.read(messengerControllerProvider);
    setState(() => _sendFailed = false);
    await messenger.sendAttachmentPlaceholder(widget.conversationId, filename: _filenameController.text.trim());
    if (!mounted) return;
    if (messenger.errorMessage != null) {
      setState(() => _sendFailed = true);
      return;
    }
    // From here the transfer goes on in the chat, on the message itself.
    veilLeaveScreen(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.watch(messengerControllerProvider);
    final error = _sendFailed ? controller.errorMessage : null;
    final isSending = controller.isBusy;
    final filename = _filenameController.text.trim();

    return VeilShell(
      title: l10n.attachmentTitle,
      child: ListView(
        children: [
          VeilInlineBanner(
            dense: true,
            icon: Icons.info_outline_rounded,
            message: l10n.attachmentPlaceholderNotice,
          ),
          const SizedBox(height: VeilSpace.lg),
          TextField(
            controller: _filenameController,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.attachmentNameInputLabel),
          ),
          const SizedBox(height: VeilSpace.xs),
          VeilCopy(
            l10n.attachmentNameCaption(AttachmentTransferService.guessContentType(filename)),
            style: theme.textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
          ),
          if (error != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.attachmentSendFailedTitle,
              message: error,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.lg),
          // Also the way to try again: a send that failed here left nothing
          // queued to retry.
          VeilButton(
            onPressed: isSending || filename.isEmpty ? null : _send,
            label: isSending ? l10n.attachmentSendingAction : l10n.attachmentSendAction,
            icon: Icons.arrow_upward_rounded,
          ),
        ],
      ),
    );
  }
}
