import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.authCreateTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.authCreateEyebrow,
            title: l10n.authCreateHeroTitle,
            body: l10n.authCreateHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.pillNoRecovery),
                VeilStatusPill(label: l10n.pillDeviceBound),
                VeilStatusPill(
                  label: l10n.pillPrivateBeta,
                  tone: VeilBannerTone.info,
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilDestructiveNotice(
            title: l10n.authCreateRestoreTitle,
            body: l10n.authCreateRestoreBody,
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilMetricStrip(
            items: [
              VeilMetricItem(
                label: l10n.authCreateMetricIdentity,
                value: l10n.authCreateMetricIdentityValue,
              ),
              VeilMetricItem(
                label: l10n.authCreateMetricRecovery,
                value: l10n.authCreateMetricRecoveryValue,
              ),
              VeilMetricItem(
                label: l10n.authCreateMetricTransfer,
                value: l10n.authCreateMetricTransferValue,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilFieldBlock(
            label: l10n.authCreateFieldLabel,
            caption: l10n.authCreateFieldCaption,
            child: TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: l10n.authCreateDisplayName,
                hintText: l10n.authCreateDisplayHint,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilActionCluster(
            children: [
              VeilButton(
                onPressed: () => context.go('/choose-handle', extra: _displayNameController.text.trim()),
                label: l10n.commonContinue,
                icon: Icons.arrow_forward_rounded,
              ),
              VeilButton(
                onPressed: () => context.push('/device-transfer'),
                tone: VeilButtonTone.secondary,
                label: l10n.authCreateTransferLabel,
                icon: Icons.phonelink_lock_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
