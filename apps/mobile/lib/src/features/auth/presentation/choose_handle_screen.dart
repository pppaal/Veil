import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_screen_intro.dart';
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

    final bindingFlow = VeilSurfaceCard(
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
    );
    final submit = VeilButton(
      onPressed: _submitting || handle.isEmpty
          ? null
          : () async {
              setState(() => _submitting = true);
              try {
                await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
                      handle: handle,
                      displayName: displayName?.isEmpty ?? true ? null : displayName,
                      deviceName: l10n.authDefaultDeviceName,
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
    );
    final failure = <Widget>[
      if (session.errorMessage != null) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: l10n.authHandleFailedTitle,
          message: veilErrorText(l10n, session.errorMessage!),
          tone: VeilBannerTone.danger,
        ),
      ],
    ];
    // The handle and the button that binds it come first; the steps the
    // binding runs through show their progress under the button.
    return VeilShell(
      title: l10n.authHandleTitle,
      padding: VeilShell.formPadding,
      child: ListView(
        children: [
          VeilScreenIntro(
            eyebrow: l10n.authHandleEyebrow,
            title: l10n.authHandleHeroTitle,
            body: l10n.authHandleHeroBody,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.authHandleFieldLabel,
            caption: l10n.authHandleFieldCaption,
            child: TextField(
              controller: _handleController,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.authHandleInputLabel,
                hintText: l10n.authHandleInputHint,
                prefixText: '@',
              ),
            ),
          ),
          ...failure,
          const SizedBox(height: VeilSpace.md),
          submit,
          const SizedBox(height: VeilSpace.md),
          bindingFlow,
        ],
      ),
    );
  }

  String _ctaLabelFor(AppSessionState session, AppLocalizations l10n) {
    if (!_submitting && !session.isAuthenticating) return l10n.authHandleBindCta;
    return switch (session.authFlowStage) {
      AuthFlowStage.idle => l10n.authHandleBindCta,
      AuthFlowStage.generatingKeys => l10n.authStageGeneratingKeys,
      AuthFlowStage.registering => l10n.authStageRegistering,
      AuthFlowStage.requestingChallenge => l10n.authStageRequestingChallenge,
      AuthFlowStage.verifying => l10n.authStageVerifying,
      AuthFlowStage.complete => l10n.authStageComplete,
    };
  }
}
