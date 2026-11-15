import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The first step of a new account: the name it shows, then on to the
/// handle, or across to moving an account from another phone. Before you
/// start has already said what losing the phone means; nothing here says
/// it again.
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
      padding: VeilShell.formPadding,
      child: ListView(
        children: [
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _continue(),
            decoration: InputDecoration(
              labelText: l10n.authCreateDisplayName,
              hintText: l10n.authCreateDisplayHint,
              helperText: l10n.authCreateFieldCaption,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilButton(onPressed: _continue, label: l10n.commonContinue),
          const SizedBox(height: VeilSpace.xs),
          VeilButton(
            onPressed: () => context.push('/device-transfer'),
            tone: VeilButtonTone.ghost,
            label: l10n.authCreateTransferLabel,
          ),
        ],
      ),
    );
  }
}
