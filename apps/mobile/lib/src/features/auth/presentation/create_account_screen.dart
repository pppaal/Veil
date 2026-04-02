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
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilInlineBanner(
            title: 'No restore path',
            message:
                'If you lose this device, your account and messages are gone. VEIL cannot restore access. This is intentional.',
            tone: VeilBannerTone.warn,
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilSectionLabel('PROFILE LABEL'),
                const SizedBox(height: VeilSpace.sm),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Optional label for this account',
                  ),
                ),
                const SizedBox(height: VeilSpace.sm),
                Text(
                  'Handles are the discovery layer. This label is presentation only.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilActionCluster(
            children: [
              FilledButton(
                onPressed: () => context.go('/choose-handle', extra: _displayNameController.text.trim()),
                child: const Text('Continue'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/device-transfer'),
                child: const Text('Transfer from old device'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
