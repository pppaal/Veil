import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VeilShell(
      title: 'Create Account',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'DEVICE BINDING',
            title: 'This device becomes your identity.',
            body:
                'VEIL binds access to the hardware in your hand. If the device is lost, the account is lost with it.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'No recovery'),
                VeilStatusPill(label: 'Device-bound'),
                VeilStatusPill(label: 'Private beta', tone: VeilBannerTone.info),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilInlineBanner(
            title: 'No restore path',
            message:
                'If you lose this device, your account and messages are gone. VEIL cannot restore access. This is intentional.',
            tone: VeilBannerTone.warn,
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilFieldBlock(
            label: 'PROFILE LABEL',
            caption: 'Handles are the discovery layer. This label is presentation only.',
            child: TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Optional label for this account',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilActionCluster(
            children: [
              VeilButton(
                onPressed: () => context.go('/choose-handle', extra: _displayNameController.text.trim()),
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
              ),
              VeilButton(
                onPressed: () => context.push('/device-transfer'),
                tone: VeilButtonTone.secondary,
                label: 'Transfer from old device',
                icon: Icons.phonelink_lock_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
