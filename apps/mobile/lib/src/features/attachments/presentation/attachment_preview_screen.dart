import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Encrypted blob only'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _filenameController,
                    decoration: const InputDecoration(labelText: 'Filename'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payload: local mock ciphertext'),
                  const Text('Server view: storage key + opaque metadata'),
                  const Text('Client flow: upload ticket -> upload complete -> encrypted message'),
                ],
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              controller.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Spacer(),
          FilledButton(
            onPressed: controller.isBusy
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
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(controller.isBusy ? 'Sending...' : 'Encrypt and send'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
