import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_grouped.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The user's handle, which peers route by, and a nickname that only this
/// device knows. No profile field is stored on the relay.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nicknameController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _edit(String? currentNickname) {
    VeilHaptics.selection();
    _nicknameController.text = currentNickname ?? '';
    setState(() => _isEditing = true);
  }

  Future<void> _save() async {
    await ref.read(appSessionProvider.notifier).updateLocalNickname(_nicknameController.text.trim());
    if (!mounted) return;
    setState(() => _isEditing = false);
    VeilToast.show(context, message: AppLocalizations.of(context).profileNicknameSaved, tone: VeilBannerTone.good);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final handle = session.handle ?? '';
    final nickname = session.displayName;
    final named = nickname != null && nickname.isNotEmpty;
    final initial = (named ? nickname : handle).characters.firstOrNull?.toUpperCase() ?? '?';

    return VeilShell(
      title: l10n.profileTitle,
      maxWidth: 560,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.lg, VeilSpace.lg, VeilSpace.xl),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primarySoft,
                border: Border.all(color: palette.strokeStrong),
              ),
              child: Text(initial, style: theme.textTheme.headlineMedium?.copyWith(color: palette.primary)),
            ),
          ),
          if (named) ...[
            const SizedBox(height: VeilSpace.sm),
            // The user's own words: drawn as typed.
            Text(nickname, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          ],
          const SizedBox(height: VeilSpace.xl),
          VeilGroup(
            label: l10n.profileHandleLabel,
            footer: l10n.profileHandleCaption,
            children: [VeilGroupRow(title: '@$handle')],
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilGroup(
            label: l10n.profileNicknameLabel,
            footer: l10n.profileNicknameCaption,
            children: [
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.all(VeilSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nicknameController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(hintText: l10n.profileNicknameHint),
                      ),
                      const SizedBox(height: VeilSpace.sm),
                      VeilActionRow(
                        children: [
                          VeilButton(
                            label: l10n.profileCancel,
                            tone: VeilButtonTone.secondary,
                            onPressed: () => setState(() => _isEditing = false),
                          ),
                          VeilButton(label: l10n.profileSaveNickname, onPressed: _save),
                        ],
                      ),
                    ],
                  ),
                )
              else
                VeilGroupRow(
                  title: named ? nickname : l10n.profileNicknameNotSet,
                  trailing: TextButton(onPressed: () => _edit(nickname), child: Text(l10n.profileEditNickname)),
                ),
            ],
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilInlineBanner(
            icon: Icons.shield_outlined,
            title: l10n.profilePrivacyTitle,
            message: l10n.profilePrivacyBody,
          ),
        ],
      ),
    );
  }
}
