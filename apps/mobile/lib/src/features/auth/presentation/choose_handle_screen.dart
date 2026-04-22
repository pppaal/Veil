import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class ChooseHandleScreen extends ConsumerStatefulWidget {
  const ChooseHandleScreen({super.key});

  @override
  ConsumerState<ChooseHandleScreen> createState() => _ChooseHandleScreenState();
}

class _ChooseHandleScreenState extends ConsumerState<ChooseHandleScreen> {
  final _handleController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final displayName = GoRouterState.of(context).extra as String?;
    final handle = _handleController.text.trim();
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.authHandleTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.authHandleEyebrow,
            title: l10n.authHandleHeroTitle,
            body: l10n.authHandleHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.pillNoContactSync),
                VeilStatusPill(label: l10n.pillHandleDiscovery),
                VeilStatusPill(label: l10n.pillDeviceBound),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.authHandleFieldLabel,
            caption: l10n.authHandleFieldCaption,
            trailing: VeilStatusPill(
              label: handle.isEmpty ? l10n.authHandleChoosePrompt : '@$handle',
              tone: handle.isEmpty ? VeilBannerTone.warn : VeilBannerTone.info,
            ),
            child: TextField(
              controller: _handleController,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.authHandleInputLabel,
                hintText: l10n.authHandleInputHint,
                prefixText: '@',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            toned: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilSectionLabel(l10n.authHandleBindingSection),
                const SizedBox(height: VeilSpace.md),
                VeilStepRow(
                  step: 1,
                  title: l10n.authHandleStep1Title,
                  body: l10n.authHandleStep1Body,
                  active: session.authFlowStage == AuthFlowStage.generatingKeys,
                  complete: session.authFlowStage.index > AuthFlowStage.generatingKeys.index,
                ),
                const SizedBox(height: VeilSpace.sm),
                VeilStepRow(
                  step: 2,
                  title: l10n.authHandleStep2Title,
                  body: l10n.authHandleStep2Body,
                  active: session.authFlowStage == AuthFlowStage.registering,
                  complete: session.authFlowStage.index > AuthFlowStage.registering.index,
                ),
                const SizedBox(height: VeilSpace.sm),
                VeilStepRow(
                  step: 3,
                  title: l10n.authHandleStep3Title,
                  body: l10n.authHandleStep3Body,
                  active: session.authFlowStage == AuthFlowStage.requestingChallenge,
                  complete: session.authFlowStage.index > AuthFlowStage.requestingChallenge.index,
                ),
                const SizedBox(height: VeilSpace.sm),
                VeilStepRow(
                  step: 4,
                  title: l10n.authHandleStep4Title,
                  body: l10n.authHandleStep4Body,
                  active: session.authFlowStage == AuthFlowStage.verifying,
                  complete: session.authFlowStage == AuthFlowStage.complete,
                ),
              ],
            ),
          ),
          if (session.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.authHandleFailedTitle,
              message: session.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
            onPressed: _submitting || handle.isEmpty
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
                            handle: handle,
                            displayName: displayName?.isEmpty ?? true ? null : displayName,
                          );
                      if (context.mounted && ref.read(appSessionProvider).isAuthenticated) {
                        context.go('/conversations');
                      }
                    } catch (_) {
                    } finally {
                      if (mounted) {
                        setState(() => _submitting = false);
                      }
                    }
                  },
            label: _ctaLabelFor(session, l10n),
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }

  String _ctaLabelFor(AppSessionState session, AppLocalizations l10n) {
    if (_submitting || session.isAuthenticating) {
      return session.authFlowStage.label;
    }
    return l10n.authHandleBindCta;
  }
}
