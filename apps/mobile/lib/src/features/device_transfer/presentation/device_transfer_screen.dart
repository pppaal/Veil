import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

class DeviceTransferScreen extends ConsumerWidget {
  const DeviceTransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(messengerControllerProvider);

    return VeilShell(
      title: 'Device Transfer',
      child: ListView(
        children: [
          const _TransferCard(
            title: '1. Initiate on old device',
            body: 'Generate a short-lived transfer token. No old device, no transfer.',
          ),
          FilledButton.tonal(
            onPressed: controller.isBusy
                ? null
                : () => ref.read(messengerControllerProvider).initTransfer(),
            child: const Text('Init transfer'),
          ),
          const SizedBox(height: 12),
          _TransferCard(
            title: '2. Scan on new device',
            body: controller.transferToken == null
                ? 'No transfer token issued yet.'
                : 'Session ${controller.transferSessionId}\nToken ${controller.transferToken}',
          ),
          FilledButton.tonal(
            onPressed: controller.isBusy || controller.transferSessionId == null
                ? null
                : () => ref.read(messengerControllerProvider).approveTransfer(),
            child: const Text('Approve on old device'),
          ),
          const SizedBox(height: 12),
          const _TransferCard(
            title: '3. Complete and revoke',
            body: 'Completion makes the new device active and revokes the old device.',
          ),
          FilledButton(
            onPressed: controller.isBusy || controller.transferToken == null
                ? null
                : () async {
                    await ref.read(messengerControllerProvider).completeTransfer();
                    if (!context.mounted) {
                      return;
                    }
                    if (ref.read(messengerControllerProvider).errorMessage == null &&
                        ref.read(messengerControllerProvider).transferStatus ==
                            'Transfer completed. Old device revoked.') {
                      await ref.read(appSessionProvider.notifier).logout();
                    }
                  },
            child: const Text('Complete transfer'),
          ),
          const SizedBox(height: 16),
          if (controller.transferStatus != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(controller.transferStatus!),
              ),
            ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(title: Text(title), subtitle: Text(body)),
    );
  }
}
