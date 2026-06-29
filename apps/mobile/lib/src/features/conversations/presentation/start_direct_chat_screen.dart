import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.startDirectTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.startDirectEyebrow,
            title: l10n.startDirectHeroTitle,
            body: l10n.startDirectHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.startDirectPillManual),
                VeilStatusPill(label: l10n.startDirectPillNoGraph),
                VeilStatusPill(label: l10n.startDirectPillDirectOnly),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: l10n.startDirectBannerTitle,
            message: l10n.startDirectBannerBody,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(
                label: l10n.startDirectMetricDiscovery,
                value: l10n.startDirectMetricDiscoveryValue,
              ),
              VeilMetricItem(
                label: l10n.startDirectMetricGraph,
                value: l10n.startDirectMetricGraphValue,
              ),
              VeilMetricItem(
                label: l10n.startDirectMetricMode,
                value: l10n.startDirectMetricModeValue,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.startDirectFieldLabel,
            trailing: _handleController.text.trim().isEmpty
                ? VeilStatusPill(label: l10n.startDirectAwaitingInput, tone: VeilBannerTone.warn)
                : VeilStatusPill(label: '@${_handleController.text.trim()}'),
            caption: l10n.startDirectFieldCaption,
            child: TextField(
              controller: _handleController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.startDirectInputLabel,
                hintText: 'icarus',
                prefixText: '@',
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.startDirectErrorTitle,
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
            label: controller.isBusy ? l10n.startDirectOpening : l10n.startDirectOpenButton,
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}
