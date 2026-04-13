import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;

  final _displayNameController = TextEditingController(text: 'Elias Craine');
  final _bioController = TextEditingController(
    text: 'Privacy is not secrecy. Building the future of opaque communication.',
  );
  final _statusController = TextEditingController(text: 'Available');

  static const _handle = 'ecraine';
  static const _conversationCount = '12';
  static const _deviceCount = '2';
  static const _accountAge = '94 days';

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    HapticFeedback.selectionClick();
    setState(() => _isEditing = !_isEditing);
    if (!_isEditing) {
      VeilToast.show(
        context,
        message: 'Profile updated locally',
        tone: VeilBannerTone.good,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return VeilShell(
      title: 'Profile',
      child: ListView(
        children: [
          // Avatar
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
                    'E',
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

          // Display Name
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
                    _displayNameController.text,
                    style: theme.textTheme.bodyLarge,
                  ),
          ),

          const SizedBox(height: VeilSpace.sm),

          // Handle (readonly)
          VeilFieldBlock(
            label: 'HANDLE',
            caption: 'Your handle cannot be changed.',
            child: Text(
              '@$_handle',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),

          const SizedBox(height: VeilSpace.sm),

          // Bio
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
                    _bioController.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
          ),

          const SizedBox(height: VeilSpace.sm),

          // Status Message
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
                        _statusController.text,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: VeilSpace.xl),

          // Privacy panel
          VeilHeroPanel(
            eyebrow: 'PRIVACY',
            title: 'Local-first profile',
            body: 'Your display name, bio, and status are stored exclusively '
                'on this device. Only your handle is shared with the relay '
                'for routing purposes.',
          ),

          const SizedBox(height: VeilSpace.xl),

          // Metrics
          VeilMetricStrip(
            items: const [
              VeilMetricItem(label: 'Conversations', value: _conversationCount),
              VeilMetricItem(label: 'Devices', value: _deviceCount),
              VeilMetricItem(label: 'Account age', value: _accountAge),
            ],
          ),

          const SizedBox(height: VeilSpace.xl),

          // Edit button
          VeilButton(
            label: _isEditing ? 'Save changes' : 'Edit profile',
            icon: _isEditing ? Icons.check_rounded : Icons.edit_outlined,
            tone: _isEditing ? VeilButtonTone.primary : VeilButtonTone.secondary,
            onPressed: _toggleEdit,
          ),

          const SizedBox(height: VeilSpace.lg),

          // Privacy banner
          VeilInlineBanner(
            message:
                'Profile data is stored locally. Only your handle is visible to the relay.',
            icon: Icons.shield_outlined,
          ),

          const SizedBox(height: VeilSpace.xxl),
        ],
      ),
    );
  }
}
