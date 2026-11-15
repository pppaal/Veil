import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_screen_intro.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The first step of a new account: the name it shows, then on to the
/// handle. The field comes first; the notice that nothing restores a lost
/// device stands once, between the field and the two ways on (a new
/// account here, or a transfer from the device that has one).
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

  void _continue() => context.go('/choose-handle', extra: _displayNameController.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.authCreateTitle,
      child: ListView(
        children: [
          // What losing the device means is said by the notice below, once.
          VeilScreenIntro(
            eyebrow: l10n.authCreateEyebrow,
            title: l10n.authCreateHeroTitle,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.authCreateFieldLabel,
            caption: l10n.authCreateFieldCaption,
            child: TextField(
              controller: _displayNameController,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _continue(),
              decoration: InputDecoration(
                labelText: l10n.authCreateDisplayName,
                hintText: l10n.authCreateDisplayHint,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilDestructiveNotice(
            title: l10n.authCreateRestoreTitle,
            body: l10n.authCreateRestoreBody,
          ),
          const SizedBox(height: VeilSpace.md),
          VeilActionCluster(
            children: [
              VeilButton(
                onPressed: _continue,
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
