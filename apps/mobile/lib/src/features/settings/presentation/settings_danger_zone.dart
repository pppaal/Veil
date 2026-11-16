import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The last group of Settings, as Signal's Account page: moving to a new
/// phone, then signing this phone out and deleting the account, both for
/// good. Each of those two opens a dialog that says what it erases and
/// asks for the user's own handle typed first, as Signal and WhatsApp ask
/// for the phone number. The account runs on one phone at a time, so there
/// is no list of devices: a move is the only way to another one.
class SettingsDangerZone extends ConsumerWidget {
  const SettingsDangerZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.read(appSessionProvider.notifier);
    final handle = '@${ref.watch(appSessionProvider.select((state) => state.handle)) ?? ''}';

    // Runs [action] once the user typed their handle. Both ask the server
    // first and can fail: the phone then keeps its state, and says so.
    Future<void> run({
      required String title,
      required String body,
      required String confirm,
      required Future<void> Function() action,
      required String failed,
      required String thenGo,
    }) async {
      final confirmed = await confirmByTypingPhrase(context, title: title, body: body, confirm: confirm, phrase: handle);
      if (confirmed != true) return;
      try {
        await action();
        if (context.mounted) context.go(thenGo);
      } catch (_) {
        if (!context.mounted) return;
        showVeilToast(context, failed, tone: VeilTone.warn);
      }
    }

    return VeilGroup(
      header: l10n.settingsSectionAccount,
      children: [
        VeilRow(
          key: const ValueKey('settings-device-transfer'),
          title: l10n.settingsDeviceTransferTitle,
          onTap: () => context.push('/device-transfer'),
        ),
        VeilRow(
          key: const ValueKey('settings-logout'),
          destructive: true,
          title: l10n.settingsLogout,
          onTap: () => run(
            title: l10n.settingsLogoutConfirmTitle,
            body: l10n.settingsLogoutConfirmBody,
            confirm: l10n.settingsLogout,
            // The server signs this phone out first; only then is it erased.
            // Unreached, nothing is erased.
            action: session.revokeCurrentDevice,
            failed: l10n.settingsLogoutFailed,
            thenGo: '/choose-handle',
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
            action: session.deleteAccount,
            failed: l10n.commonError,
            thenGo: '/splash',
          ),
        ),
      ],
    );
  }
}

/// Asks the user to type [phrase] (their handle, "@alex") before an action
/// that cannot be undone. Returns true only when they typed it and pressed
/// [confirm].
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

  // Letter case and the "@" are not the point of the phrase; typing it is.
  static String _bare(String text) {
    final trimmed = text.trim().toLowerCase();
    return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  }

  bool get _matches => _bare(_typed.text).isNotEmpty && _bare(_typed.text) == _bare(widget.phrase);

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
            textCapitalization: TextCapitalization.none,
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
