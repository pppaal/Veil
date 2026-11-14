import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Sends an attachment into a conversation. This build has no file picker:
/// it sends a small placeholder file under the name typed here, along the
/// path a real attachment takes (stage, ticket, upload, message).
class AttachmentPreviewScreen extends ConsumerStatefulWidget {
  const AttachmentPreviewScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<AttachmentPreviewScreen> createState() => _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends ConsumerState<AttachmentPreviewScreen> {
  final _filenameController = TextEditingController(text: 'dossier.enc');
  bool _submitted = false;

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(messengerControllerProvider);
    final hasError = controller.errorMessage != null;
    final isSending = controller.isBusy;
    final filename = _filenameController.text.trim();
    final contentType = _guessContentType(filename);

    return VeilShell(
      title: l10n.attachmentTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.attachmentHeroEyebrow,
            title: l10n.attachmentHeroTitle,
            body: l10n.attachmentHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.attachmentPillOpaqueBlob),
                VeilStatusPill(label: l10n.attachmentPillMetadataOnlyRelay),
                VeilStatusPill(label: l10n.attachmentPillNoPlaintextPush),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.attachmentNameLabel,
            caption: l10n.attachmentNameCaption,
            trailing: VeilStatusPill(label: contentType),
            child: TextField(
              controller: _filenameController,
              decoration: InputDecoration(labelText: l10n.attachmentNameInputLabel),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: l10n.attachmentRelayPolicyTitle,
            message: l10n.attachmentRelayPolicyBody,
            tone: VeilBannerTone.info,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(label: l10n.attachmentMetricType, value: contentType),
              VeilMetricItem(label: l10n.attachmentMetricUpload, value: l10n.attachmentMetricUploadValue),
              VeilMetricItem(label: l10n.attachmentMetricBlob, value: l10n.attachmentMetricBlobValue),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            toned: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilSectionLabel(l10n.attachmentStepsSection),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 1,
                  title: l10n.attachmentStep1Title,
                  body: l10n.attachmentStep1Body,
                  active: isSending && !_submitted,
                  complete: _submitted || hasError,
                ),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 2,
                  title: l10n.attachmentStep2Title,
                  body: l10n.attachmentStep2Body,
                  active: isSending,
                  complete: _submitted && !hasError,
                ),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 3,
                  title: l10n.attachmentStep3Title,
                  body: l10n.attachmentStep3Body,
                  active: isSending,
                  complete: _submitted && !hasError,
                ),
              ],
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.attachmentSendFailedTitle,
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ] else if (_submitted) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.attachmentQueuedTitle,
              message: l10n.attachmentQueuedBody,
              tone: VeilBannerTone.good,
            ),
          ],
          const SizedBox(height: VeilSpace.xl),
          VeilActionCluster(
            children: [
              VeilButton(
                onPressed: isSending || _filenameController.text.trim().isEmpty
                    ? null
                    : () async {
                        setState(() => _submitted = true);
                        await ref.read(messengerControllerProvider).sendAttachmentPlaceholder(
                              widget.conversationId,
                              filename: _filenameController.text.trim(),
                            );
                        if (context.mounted &&
                            ref.read(messengerControllerProvider).errorMessage == null) {
                          Navigator.of(context).pop();
                        }
                      },
                label: isSending ? l10n.attachmentSendingAction : l10n.attachmentSendAction,
                icon: Icons.arrow_upward_rounded,
              ),
              if (hasError)
                VeilButton(
                  onPressed: isSending
                      ? null
                      : () => ref
                          .read(messengerControllerProvider)
                          .retryPendingMessages(widget.conversationId),
                  tone: VeilButtonTone.secondary,
                  label: l10n.chatRetryFailedSendsAction,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _guessContentType(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalized.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }
}
