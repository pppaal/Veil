import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_grouped.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The end of the settings screen: the four actions that take this device,
/// or the account, away for good, under the notice that nothing brings
/// them back. Each says what it erases and asks for a typed phrase first.
class SettingsDangerZone extends ConsumerWidget {
  const SettingsDangerZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.read(appSessionProvider.notifier);

    // Runs [action] once the user typed [phrase]. An action that asks the
    // relay first can fail: the device then keeps its state, and says so.
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
        VeilToast.show(context, message: l10n.commonError, tone: VeilBannerTone.warn);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VeilDestructiveNotice(title: l10n.settingsNoRecoveryPath, body: l10n.settingsDestructiveNoticeBody),
        const SizedBox(height: VeilSpace.md),
        VeilGroup(
          label: l10n.settingsSectionIrreversible,
          children: [
            VeilGroupRow(
              key: const ValueKey('settings-logout'),
              destructive: true,
              icon: Icons.logout,
              title: l10n.settingsLogout,
              subtitle: l10n.settingsLogoutSubtitle,
              onTap: () => run(
                title: l10n.settingsLogoutConfirmTitle,
                body: l10n.settingsLogoutConfirmBody,
                confirm: l10n.settingsLogout,
                phrase: l10n.settingsLogoutConfirmPhrase,
                action: session.logout,
                thenGo: '/create-account',
              ),
            ),
            VeilGroupRow(
              key: const ValueKey('settings-wipe'),
              destructive: true,
              icon: Icons.layers_clear_outlined,
              title: l10n.settingsWipeLocal,
              subtitle: l10n.settingsWipeLocalSubtitle,
              onTap: () => run(
                title: l10n.settingsWipeConfirmTitle,
                body: l10n.settingsWipeConfirmBody,
                confirm: l10n.settingsWipeConfirmAction,
                phrase: l10n.settingsWipeConfirmPhrase,
                action: session.wipeLocalDeviceState,
                thenGo: '/splash',
              ),
            ),
            VeilGroupRow(
              key: const ValueKey('settings-revoke'),
              destructive: true,
              icon: Icons.phonelink_erase_outlined,
              title: l10n.settingsRevokeTitle,
              subtitle: l10n.settingsRevokeSubtitle,
              onTap: () => run(
                title: l10n.settingsRevokeConfirmTitle,
                body: l10n.settingsRevokeConfirmBody,
                confirm: l10n.settingsRevokeConfirmAction,
                phrase: l10n.settingsRevokeConfirmPhrase,
                // The relay did not revoke it: this device keeps its state.
                action: session.revokeCurrentDevice,
                thenGo: '/create-account',
              ),
            ),
            VeilGroupRow(
              key: const ValueKey('settings-delete-account'),
              destructive: true,
              icon: Icons.delete_forever_outlined,
              title: l10n.settingsDeleteAccountAction,
              subtitle: l10n.settingsDeleteAccountBody,
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
  bool get _matches => _typed.text.trim().toUpperCase() == widget.phrase.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return AlertDialog(
      // On a small phone with the keyboard up the dialog scrolls.
      scrollable: true,
      title: VeilCopy(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeilCopy(widget.body),
          const SizedBox(height: VeilSpace.md),
          VeilCopy(l10n.settingsTypePhraseToContinue(widget.phrase)),
          const SizedBox(height: VeilSpace.sm),
          // Not focused on opening: the keyboard would cover half of what
          // there is to read before typing.
          TextField(
            controller: _typed,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: widget.phrase),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: palette.danger, foregroundColor: palette.canvas),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
