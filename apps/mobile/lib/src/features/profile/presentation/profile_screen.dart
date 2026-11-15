import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Who the user is to themselves: the avatar, the nickname this phone
/// keeps for them and the handle people find them by, with the nickname
/// edited in place. No profile field is stored on the server.
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
    showVeilToast(context, AppLocalizations.of(context).profileNicknameSaved, tone: VeilTone.good);
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

    return VeilShell(
      title: l10n.profileTitle,
      grouped: true,
      maxWidth: 560,
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
                Text(
                  named ? nickname : '@$handle',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                if (named) ...[
                  const SizedBox(height: VeilSpace.xxs),
                  Text(
                    '@$handle',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                  ),
                ],
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
                trailing: !changed
                    ? null
                    : TextButton(
                        onPressed: _saving ? null : _save,
                        child: Text(l10n.profileSaveNickname),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
