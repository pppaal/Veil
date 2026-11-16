import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/identity/issued_handle.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The one screen a new account takes: a handle, then the button that
/// creates the account, and under it the way across to moving an account
/// from another phone. The handle's rules show only as the field's error,
/// when what was typed breaks them.
class ChooseHandleScreen extends ConsumerStatefulWidget {
  const ChooseHandleScreen({super.key});

  @override
  ConsumerState<ChooseHandleScreen> createState() => _ChooseHandleScreenState();
}

/// Characters an issued handle can hold (see [isIssuableHandle]).
final _issuableCharacters = RegExp(r'^[a-z0-9._]*$');

class _ChooseHandleScreenState extends ConsumerState<ChooseHandleScreen> {
  final _handleController = TextEditingController();
  bool _submitting = false;

  // Set when a handle that breaks the rules was submitted; it goes once the
  // handle is changed.
  bool _rejectedLocally = false;

  // The failure the user has typed over since it was shown: it goes once
  // they change the handle, and the next attempt shows its own.
  String? _dismissedError;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _submit(String handle) async {
    if (!isIssuableHandle(handle)) {
      setState(() => _rejectedLocally = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _dismissedError = null;
    });
    try {
      await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
            handle: handle,
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
    final handle = _handleController.text.trim();
    final l10n = AppLocalizations.of(context);
    final working = _submitting || session.isAuthenticating;
    final error = session.errorMessage;
    final breaksRules = handle.length > issuedHandleMaxLength || !_issuableCharacters.hasMatch(handle);
    final String? shownError;
    if (!working && (breaksRules || _rejectedLocally)) {
      shownError = l10n.authHandleInvalid;
    } else if (working || error == null || error == _dismissedError) {
      shownError = null;
    } else {
      shownError = veilErrorText(l10n, error);
    }

    // The handle, then the button that creates the account. While it
    // works, the button holds a spinner and says so. Why the account was
    // not created is the field's error, in place of its footer, until the
    // handle is changed.
    return VeilShell(
      title: l10n.authHandleTitle,
      padding: VeilShell.formPadding,
      child: ListView(
        children: [
          TextField(
            controller: _handleController,
            enabled: !_submitting,
            onChanged: (_) => setState(() {
              _rejectedLocally = false;
              _dismissedError = ref.read(appSessionProvider).errorMessage;
            }),
            onSubmitted: (_) {
              if (handle.isNotEmpty && !working) _submit(_handleController.text.trim());
            },
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.authHandleInputLabel,
              hintText: l10n.authHandleInputHint,
              prefixText: '@',
              helperText: l10n.authHandleFindCaption,
              errorText: shownError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          if (working)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: VeilSpace.xs),
                    Flexible(child: Text(l10n.authCreating, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            )
          else
            VeilButton(
              onPressed: handle.isEmpty || breaksRules ? null : () => _submit(handle),
              label: l10n.authHandleBindCta,
            ),
          const SizedBox(height: VeilSpace.xs),
          VeilButton(
            onPressed: working ? null : () => context.push('/device-transfer'),
            tone: VeilButtonTone.ghost,
            label: l10n.authCreateTransferLabel,
          ),
        ],
      ),
    );
  }
}
