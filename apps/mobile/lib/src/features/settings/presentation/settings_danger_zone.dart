import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The last group of Settings: the four actions that take this device, or
/// the account, away for good. Each row opens a dialog that says what it
/// erases and asks for a typed phrase first.
class SettingsDangerZone extends ConsumerWidget {
  const SettingsDangerZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.read(appSessionProvider.notifier);

    // Runs [action] once the user typed [phrase]. An action that asks the
    // server first can fail: the device then keeps its state, and says so.
    Future<void> run({
      required String title,
      required String body,
      required String confirm,
      required String phrase,
      required Future<void> Function() action,
      required String thenGo,
    }) async {
      final confirmed = await confirmByTypingPhrase(context, title: title, body: body, confirm: confirm, phrase: phrase);
      if (confirmed != true) return;
      try {
        await action();
        if (context.mounted) context.go(thenGo);
      } catch (_) {
        if (!context.mounted) return;
        showVeilToast(context, l10n.commonError, tone: VeilTone.warn);
      }
    }

    return VeilGroup(
      header: l10n.settingsSectionAccount,
      children: [
        VeilRow(
          key: const ValueKey('settings-logout'),
          destructive: true,
          title: l10n.settingsLogout,
          onTap: () => run(
            title: l10n.settingsLogoutConfirmTitle,
            body: l10n.settingsLogoutConfirmBody,
            confirm: l10n.settingsLogout,
            phrase: l10n.settingsLogoutConfirmPhrase,
            action: session.logout,
            thenGo: '/create-account',
          ),
        ),
        VeilRow(
          key: const ValueKey('settings-wipe'),
          destructive: true,
          title: l10n.settingsWipeLocal,
          onTap: () => run(
            title: l10n.settingsWipeConfirmTitle,
            body: l10n.settingsWipeConfirmBody,
            confirm: l10n.settingsWipeConfirmAction,
            phrase: l10n.settingsWipeConfirmPhrase,
            action: session.wipeLocalDeviceState,
            thenGo: '/splash',
          ),
        ),
        VeilRow(
          key: const ValueKey('settings-revoke'),
          destructive: true,
          title: l10n.settingsRevokeTitle,
          onTap: () => run(
            title: l10n.settingsRevokeConfirmTitle,
            body: l10n.settingsRevokeConfirmBody,
            confirm: l10n.settingsRevokeConfirmAction,
            phrase: l10n.settingsRevokeConfirmPhrase,
            // The server did not revoke it: this device keeps its state.
            action: session.revokeCurrentDevice,
            thenGo: '/create-account',
          ),
        ),
        VeilRow(
          key: const ValueKey('settings-delete-account'),
          destructive: true,
          title: l10n.settingsDeleteAccountAction,
          onTap: () => run(
            title: l10n.settingsDeleteAccountConfirmHeadline,
            body: l10n.settingsDeleteAccountBody,
            confirm: l10n.settingsDeleteAccountAction,
            phrase: l10n.settingsDeleteAccountConfirmPhrase,
            action: session.deleteAccount,
            thenGo: '/splash',
          ),
        ),
      ],
    );
  }
}

/// Asks the user to type [phrase] before an action that cannot be undone.
/// Returns true only when they typed it and pressed [confirm].
Future<bool?> confirmByTypingPhrase(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String phrase,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _TypedPhraseDialog(title: title, body: body, confirm: confirm, phrase: phrase),
  );
}

class _TypedPhraseDialog extends StatefulWidget {
  const _TypedPhraseDialog({required this.title, required this.body, required this.confirm, required this.phrase});

  final String title;
  final String body;
  final String confirm;
  final String phrase;

  @override
  State<_TypedPhraseDialog> createState() => _TypedPhraseDialogState();
}

class _TypedPhraseDialogState extends State<_TypedPhraseDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  // Letter case is not the point of the phrase; typing it is.
  bool get _matches => _typed.text.trim().toLowerCase() == widget.phrase.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return AlertDialog(
      // On a small phone with the keyboard up the dialog scrolls.
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: VeilSpace.md),
          Text(l10n.settingsTypePhraseToContinue(widget.phrase)),
          const SizedBox(height: VeilSpace.sm),
          // Not focused on opening: the keyboard would cover half of what
          // there is to read before typing.
          TextField(
            controller: _typed,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(isDense: true, hintText: widget.phrase),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
