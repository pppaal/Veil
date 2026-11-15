import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
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

  // The failure the user has typed over since it was shown: it goes once
  // they change the handle, and the next attempt shows its own.
  String? _dismissedError;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _submit(String handle, String? displayName) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _dismissedError = null;
    });
    try {
      await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
            handle: handle,
            displayName: displayName?.isEmpty ?? true ? null : displayName,
            deviceName: l10n.authDefaultDeviceName,
          );
      if (mounted && ref.read(appSessionProvider).isAuthenticated) {
        context.go('/conversations');
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final displayName = GoRouterState.of(context).extra as String?;
    final handle = _handleController.text.trim();
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final working = _submitting || session.isAuthenticating;
    final error = session.errorMessage;
    final shownError = working || error == null || error == _dismissedError ? null : veilErrorText(l10n, error);

    // The handle, then the button that creates the account. While it
    // works, the button holds a spinner and one line under it says which
    // stage it is at. Why the account was not created is the field's
    // error, in place of its helper line, until the handle is changed.
    return VeilShell(
      title: l10n.authHandleTitle,
      padding: VeilShell.formPadding,
      child: ListView(
        children: [
          TextField(
            controller: _handleController,
            enabled: !_submitting,
            onChanged: (_) => setState(() => _dismissedError = ref.read(appSessionProvider).errorMessage),
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.authHandleInputLabel,
              hintText: l10n.authHandleInputHint,
              prefixText: '@',
              helperText: l10n.authHandleFindCaption,
              helperMaxLines: 3,
              errorText: shownError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          if (working)
            const SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            VeilButton(
              onPressed: handle.isEmpty ? null : () => _submit(handle, displayName),
              label: l10n.authHandleBindCta,
            ),
          if (working) ...[
            const SizedBox(height: VeilSpace.xs),
            Text(
              _stageLabelFor(session, l10n),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _stageLabelFor(AppSessionState session, AppLocalizations l10n) => switch (session.authFlowStage) {
        AuthFlowStage.idle => l10n.authStageGeneratingKeys,
        AuthFlowStage.generatingKeys => l10n.authStageGeneratingKeys,
        AuthFlowStage.registering => l10n.authStageRegistering,
        AuthFlowStage.requestingChallenge => l10n.authStageRequestingChallenge,
        AuthFlowStage.verifying => l10n.authStageVerifying,
        AuthFlowStage.complete => l10n.authStageComplete,
      };
}
