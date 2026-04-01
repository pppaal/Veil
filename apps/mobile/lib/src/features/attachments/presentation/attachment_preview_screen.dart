import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
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

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(messengerControllerProvider);

    return VeilShell(
      title: 'Attachment Preview',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'ATTACHMENT FLOW',
            title: 'Encrypted blob only.',
            body:
                'The sender encrypts locally, uploads an opaque blob, and then sends an encrypted envelope with the attachment reference.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VeilSectionLabel('LOCAL ATTACHMENT LABEL'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _filenameController,
                    decoration: const InputDecoration(labelText: 'Filename'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      VeilStatusPill(label: 'Payload: opaque dev blob'),
                      VeilStatusPill(label: 'Server sees metadata only'),
                      VeilStatusPill(label: 'No plaintext push'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Client flow: upload ticket -> upload blob -> upload complete -> encrypted message.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const VeilInlineBanner(
            title: 'Internal alpha note',
            message:
                'This build still uses the mock crypto adapter, but the attachment path preserves the encrypted-envelope architecture.',
            tone: VeilBannerTone.info,
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 16),
            VeilInlineBanner(
              title: 'Attachment send failed',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: controller.isBusy || _filenameController.text.trim().isEmpty
                ? null
                : () async {
                    await ref.read(messengerControllerProvider).sendAttachmentPlaceholder(
                          widget.conversationId,
                          filename: _filenameController.text.trim(),
                        );
                    if (context.mounted &&
                        ref.read(messengerControllerProvider).errorMessage == null) {
                      Navigator.of(context).pop();
                    }
                  },
            child: Text(controller.isBusy ? 'Encrypting and sending' : 'Encrypt and send'),
          ),
        ],
      ),
    );
  }
}
