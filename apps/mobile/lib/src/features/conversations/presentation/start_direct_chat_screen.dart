import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
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
            body:
                'Enter the handle directly. VEIL does not scan contacts, phone books, or social graphs.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'Manual discovery'),
                VeilStatusPill(label: 'No social graph'),
                VeilStatusPill(label: 'Direct only'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilInlineBanner(
            title: 'Deliberate discovery',
            message:
                'Conversations open only when you know the exact handle. There is no graph expansion layer here.',
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilMetricStrip(
            items: [
              VeilMetricItem(label: 'Discovery', value: 'Manual'),
              VeilMetricItem(label: 'Graph', value: 'None'),
              VeilMetricItem(label: 'Mode', value: 'Direct 1:1'),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: 'TARGET HANDLE',
            trailing: _handleController.text.trim().isEmpty
                ? const VeilStatusPill(label: 'Awaiting input', tone: VeilBannerTone.warn)
                : VeilStatusPill(label: '@${_handleController.text.trim()}'),
            caption: 'Discovery stays manual. Direct conversations only.',
            child: TextField(
              controller: _handleController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Handle',
                hintText: 'icarus',
                prefixText: '@',
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Unable to open conversation',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
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
            label: controller.isBusy ? 'Opening conversation' : 'Open direct conversation',
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}
