import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Who the user is to themselves: the avatar, the name this phone keeps for
/// them and the handle people find them by (a tap copies it, as Telegram's
/// username), with the name edited in place and saved from the bar. No
/// profile field is stored on the server.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _nickname = TextEditingController(text: ref.read(appSessionProvider).displayName ?? '');
  final _focus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _nickname.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _changed(String? saved) => _nickname.text.trim() != (saved ?? '');

  Future<void> _save() async {
    if (_saving) return;
    final typed = _nickname.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(appSessionProvider.notifier).updateLocalNickname(typed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    _nickname.text = typed;
    _focus.unfocus();
    showVeilToast(context, AppLocalizations.of(context).profileNicknameSaved);
  }

  Future<void> _copyHandle(String handle) async {
    final copied = AppLocalizations.of(context).profileHandleCopied;
    await Clipboard.setData(ClipboardData(text: '@$handle'));
    if (!mounted) return;
    showVeilToast(context, copied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final handle = session.handle ?? '';
    final nickname = session.displayName;
    final named = nickname != null && nickname.isNotEmpty;
    final changed = _changed(nickname);

    // The handle, wherever it is drawn: a tap copies it.
    Widget handleText(TextStyle? style) => Semantics(
          button: true,
          child: InkWell(
            key: const ValueKey('profile-handle'),
            borderRadius: BorderRadius.circular(VeilRadius.sm),
            onTap: () => _copyHandle(handle),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs, vertical: VeilSpace.xxs),
              child: Text('@$handle', textAlign: TextAlign.center, style: style),
            ),
          ),
        );

    return VeilShell(
      title: l10n.profileTitle,
      grouped: true,
      maxWidth: 560,
      actions: [
        if (changed)
          TextButton(
            key: const ValueKey('profile-save'),
            onPressed: _saving ? null : _save,
            child: Text(l10n.profileSaveNickname),
          ),
      ],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: VeilSpace.xl, bottom: VeilSpace.xxl),
        children: [
          Center(child: VeilAvatar(name: named ? nickname : handle, seed: handle, size: 72)),
          const SizedBox(height: VeilSpace.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
            child: Column(
              children: [
                // The user's own words: drawn as typed.
                if (named) ...[
                  Text(nickname, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  handleText(theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                ] else
                  handleText(theme.textTheme.headlineMedium),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.xs),
          VeilGroup(
            header: l10n.profileNicknameHeader,
            footer: l10n.profileNicknameFooter,
            children: [
              VeilRow.field(
                // The group's header names the field on screen; a screen
                // reader hears it on the field itself.
                field: Semantics(
                  label: l10n.profileNicknameHeader,
                  child: TextField(
                    key: const ValueKey('profile-nickname'),
                    controller: _nickname,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_changed(ref.read(appSessionProvider).displayName)) _save();
                    },
                    decoration: InputDecoration(hintText: l10n.profileNicknameHint),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
