import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/profile_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  bool _fieldsHydrated = false;

  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _statusController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _hydrateFromSnapshot(ProfileSnapshot snapshot) {
    if (_fieldsHydrated) return;
    _displayNameController.text = snapshot.displayName ?? '';
    _bioController.text = snapshot.bio ?? '';
    _statusController.text = snapshot.statusMessage ?? '';
    _fieldsHydrated = true;
  }

  Future<void> _onEditPressed(ProfileController controller) async {
    HapticFeedback.selectionClick();
    if (_isEditing) {
      final snapshot = controller.profile;
      final currentDisplay = snapshot?.displayName ?? '';
      final currentBio = snapshot?.bio ?? '';
      final currentStatus = snapshot?.statusMessage ?? '';

      final nextDisplay = _displayNameController.text.trim();
      final nextBio = _bioController.text.trim();
      final nextStatus = _statusController.text.trim();

      final success = await controller.updateProfile(
        displayName:
            nextDisplay != currentDisplay.trim() ? nextDisplay : null,
        bio: nextBio != currentBio.trim() ? nextBio : null,
        statusMessage:
            nextStatus != currentStatus.trim() ? nextStatus : null,
      );

      if (!mounted) return;
      if (success) {
        setState(() {
          _isEditing = false;
          _fieldsHydrated = false;
        });
        VeilToast.show(
          context,
          message: 'Profile updated',
          tone: VeilBannerTone.good,
        );
      }
    } else {
      setState(() => _isEditing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final controller = ref.watch(profileControllerProvider);
    final profile = controller.profile;

    if (profile != null && !_isEditing) {
      _hydrateFromSnapshot(profile);
    }

    return VeilShell(
      title: 'Profile',
      child: RefreshIndicator(
        onRefresh: () => controller.refresh(),
        child: ListView(
          children: [
            if (controller.isLoading && profile == null) ...[
              const SizedBox(height: VeilSpace.xl),
              const Center(child: CircularProgressIndicator()),
            ] else if (profile == null) ...[
              const SizedBox(height: VeilSpace.md),
              VeilInlineBanner(
                title: 'Profile unavailable',
                message: controller.errorMessage ??
                    'Unable to load your profile from the relay.',
                tone: VeilBannerTone.danger,
              ),
            ] else ...[
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.primarySoft,
                        border: Border.all(
                          color: palette.strokeStrong,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        (profile.displayName?.isNotEmpty == true
                                ? profile.displayName!
                                : profile.handle)
                            .characters
                            .first
                            .toUpperCase(),
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: palette.primary,
                          fontSize: 36,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.surfaceRaised,
                          border: Border.all(color: palette.stroke),
                        ),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: VeilIconSize.sm,
                          color: palette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: VeilSpace.xl),
              VeilFieldBlock(
                label: 'DISPLAY NAME',
                child: _isEditing
                    ? TextField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(
                          hintText: 'Enter display name',
                        ),
                      )
                    : Text(
                        profile.displayName?.isNotEmpty == true
                            ? profile.displayName!
                            : 'Not set',
                        style: theme.textTheme.bodyLarge,
                      ),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilFieldBlock(
                label: 'HANDLE',
                caption: 'Your handle cannot be changed.',
                child: Text(
                  '@${profile.handle}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilFieldBlock(
                label: 'BIO',
                child: _isEditing
                    ? TextField(
                        controller: _bioController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Write something about yourself',
                        ),
                      )
                    : Text(
                        profile.bio?.isNotEmpty == true
                            ? profile.bio!
                            : 'No bio yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilFieldBlock(
                label: 'STATUS MESSAGE',
                child: _isEditing
                    ? TextField(
                        controller: _statusController,
                        decoration: const InputDecoration(
                          hintText: 'Set a status',
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.success,
                            ),
                          ),
                          const SizedBox(width: VeilSpace.xs),
                          Text(
                            profile.statusMessage?.isNotEmpty == true
                                ? profile.statusMessage!
                                : 'Available',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: VeilSpace.md),
                VeilInlineBanner(
                  title: 'Save failed',
                  message: controller.errorMessage!,
                  tone: VeilBannerTone.danger,
                ),
              ],
              const SizedBox(height: VeilSpace.xl),
              const VeilHeroPanel(
                eyebrow: 'PRIVACY',
                title: 'Local-first profile',
                body:
                    'Your display name, bio, and status are stored exclusively on this device and relay. Only your handle is shared with other users for routing purposes.',
              ),
              const SizedBox(height: VeilSpace.xl),
              VeilMetricStrip(
                items: [
                  const VeilMetricItem(
                    label: 'Handle',
                    value: 'Fixed',
                  ),
                  VeilMetricItem(
                    label: 'Account age',
                    value: profile.accountAgeLabel,
                  ),
                  const VeilMetricItem(
                    label: 'Storage',
                    value: 'Local',
                  ),
                ],
              ),
              const SizedBox(height: VeilSpace.xl),
              VeilButton(
                label: controller.isSaving
                    ? 'Saving\u2026'
                    : (_isEditing ? 'Save changes' : 'Edit profile'),
                icon: _isEditing
                    ? Icons.check_rounded
                    : Icons.edit_outlined,
                tone: _isEditing
                    ? VeilButtonTone.primary
                    : VeilButtonTone.secondary,
                onPressed: controller.isSaving
                    ? null
                    : () => _onEditPressed(controller),
              ),
              if (_isEditing) ...[
                const SizedBox(height: VeilSpace.sm),
                VeilButton(
                  label: 'Cancel',
                  icon: Icons.close_rounded,
                  tone: VeilButtonTone.secondary,
                  onPressed: controller.isSaving
                      ? null
                      : () {
                          setState(() {
                            _isEditing = false;
                            _fieldsHydrated = false;
                          });
                        },
                ),
              ],
              const SizedBox(height: VeilSpace.lg),
              const VeilInlineBanner(
                message:
                    'Profile data is stored on the relay so your devices stay in sync. Only your handle is visible to peers.',
                icon: Icons.shield_outlined,
              ),
              const SizedBox(height: VeilSpace.xxl),
            ],
          ],
        ),
      ),
    );
  }
}
