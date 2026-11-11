import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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

  Future<void> _onEditPressed(String? currentNickname) async {
    VeilHaptics.selection();
    if (!_isEditing) {
      _nicknameController.text = currentNickname ?? '';
      setState(() => _isEditing = true);
      return;
    }
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
    final initial = (nickname?.isNotEmpty == true ? nickname! : handle).characters.firstOrNull?.toUpperCase() ?? '?';

    return VeilShell(
      title: l10n.profileTitle,
      child: ListView(
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primarySoft,
                border: Border.all(color: palette.strokeStrong, width: 2),
              ),
              child: Text(
                initial,
                style: theme.textTheme.displayLarge?.copyWith(color: palette.primary, fontSize: 36),
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilFieldBlock(
            label: l10n.profileHandleLabel,
            caption: l10n.profileHandleCaption,
            child: Text(
              '@$handle',
              style: theme.textTheme.bodyLarge?.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilFieldBlock(
            label: l10n.profileNicknameLabel,
            caption: l10n.profileNicknameCaption,
            child: _isEditing
                ? TextField(
                    controller: _nicknameController,
                    decoration: InputDecoration(hintText: l10n.profileNicknameHint),
                  )
                : Text(
                    nickname?.isNotEmpty == true ? nickname! : l10n.profileNicknameNotSet,
                    style: theme.textTheme.bodyLarge,
                  ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilHeroPanel(
            eyebrow: l10n.profilePrivacyEyebrow,
            title: l10n.profilePrivacyTitle,
            body: l10n.profilePrivacyBody,
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
            label: _isEditing ? l10n.profileSaveNickname : l10n.profileEditNickname,
            icon: _isEditing ? Icons.check_rounded : Icons.edit_outlined,
            tone: _isEditing ? VeilButtonTone.primary : VeilButtonTone.secondary,
            onPressed: () => _onEditPressed(nickname),
          ),
          if (_isEditing) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilButton(
              label: l10n.profileCancel,
              icon: Icons.close_rounded,
              tone: VeilButtonTone.secondary,
              onPressed: () => setState(() => _isEditing = false),
            ),
          ],
          const SizedBox(height: VeilSpace.xxl),
        ],
      ),
    );
  }
}
