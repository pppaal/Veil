import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No contact sync. Enter the handle directly.'),
          const SizedBox(height: 20),
          TextField(
            controller: _handleController,
            decoration: const InputDecoration(labelText: 'Handle', hintText: 'icarus'),
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
                    await ref
                        .read(messengerControllerProvider)
                        .startConversationByHandle(_handleController.text.trim());
                    if (context.mounted &&
                        ref.read(messengerControllerProvider).errorMessage == null) {
                      context.pop();
                    }
                  },
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(controller.isBusy ? 'Opening...' : 'Open channel'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
