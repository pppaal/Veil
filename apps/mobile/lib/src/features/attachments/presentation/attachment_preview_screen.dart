import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

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
    final controller = ref.watch(messengerControllerProvider);
    final hasError = controller.errorMessage != null;
    final isSending = controller.isBusy;
    final filename = _filenameController.text.trim();
    final contentType = _guessContentType(filename);

    return VeilShell(
      title: 'Attachment Preview',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'ATTACHMENT FLOW',
            title: 'Encrypted blob only.',
            body:
                'The sender encrypts locally, uploads an opaque blob, and then sends an encrypted envelope with the attachment reference.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'Opaque blob'),
                VeilStatusPill(label: 'Metadata-only relay'),
                VeilStatusPill(label: 'No plaintext push'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: 'LOCAL ATTACHMENT LABEL',
            caption:
                'Client flow: stage a local opaque blob, request an upload ticket, stream the blob, finalize the object, then send the encrypted attachment envelope.',
            trailing: VeilStatusPill(label: contentType),
            child: TextField(
              controller: _filenameController,
              decoration: const InputDecoration(labelText: 'Filename'),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          const VeilInlineBanner(
            title: 'Relay policy',
            message:
                'Private beta currently allows JPEG, PNG, WEBP, PDF, and opaque binary payloads. The relay never receives plaintext filenames or attachment keys.',
            tone: VeilBannerTone.info,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(label: 'MIME', value: contentType),
              const VeilMetricItem(label: 'Upload', value: 'Ticketed'),
              const VeilMetricItem(label: 'Blob', value: 'Opaque'),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            toned: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilSectionLabel('SEND LIFECYCLE'),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 1,
                  title: 'Ticket',
                  body: 'Request a scoped upload URL for the opaque blob.',
                  active: isSending && !_submitted,
                  complete: _submitted || hasError,
                ),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 2,
                  title: 'Blob upload',
                  body:
                      'Upload ciphertext-like bytes. Retry reuses the local opaque temp blob and renews the presigned ticket if it expires.',
                  active: isSending,
                  complete: _submitted && !hasError,
                ),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 3,
                  title: 'Envelope send',
                  body:
                      'Queue the encrypted attachment reference into the conversation and clear the local temp blob after finalizing.',
                  active: isSending,
                  complete: _submitted && !hasError,
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilInlineBanner(
            title: 'Private beta note',
            message:
                'This build still uses the mock crypto adapter, but the attachment path preserves the encrypted-envelope architecture.',
            tone: VeilBannerTone.info,
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Attachment send failed',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ] else if (_submitted) ...[
            const SizedBox(height: VeilSpace.md),
            const VeilInlineBanner(
              title: 'Queued locally',
              message:
                  'The attachment flow now continues inside the conversation. Progress, retry, and cancel state will follow the staged message bubble.',
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
                label: isSending ? 'Encrypting and sending' : 'Encrypt and send',
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
                  label: 'Retry queued failures',
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
