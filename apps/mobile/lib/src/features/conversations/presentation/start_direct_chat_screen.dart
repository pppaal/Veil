import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class StartDirectChatScreen extends ConsumerStatefulWidget {
  const StartDirectChatScreen({super.key});

  @override
  ConsumerState<StartDirectChatScreen> createState() => _StartDirectChatScreenState();
}

class _StartDirectChatScreenState extends ConsumerState<StartDirectChatScreen> {
  final _handleController = TextEditingController();

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(messengerControllerProvider);

    return VeilShell(
      title: 'Find by Handle',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'DIRECT DISCOVERY',
            title: 'No contact sync.',
            body: 'Enter the handle directly. VEIL does not scan contacts, phone books, or social graphs.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VeilSectionLabel('TARGET HANDLE'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _handleController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Handle',
                      hintText: 'icarus',
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Discovery stays manual. Direct channels only.'),
                ],
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 16),
            VeilInlineBanner(
              title: 'Unable to open channel',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: controller.isBusy || _handleController.text.trim().isEmpty
                ? null
                : () async {
                    await ref
                        .read(messengerControllerProvider)
                        .startConversationByHandle(_handleController.text.trim());
                    if (context.mounted &&
                        ref.read(messengerControllerProvider).errorMessage == null) {
                      context.pop();
                    }
                  },
            child: Text(controller.isBusy ? 'Opening channel' : 'Open direct channel'),
          ),
        ],
      ),
    );
  }
}
