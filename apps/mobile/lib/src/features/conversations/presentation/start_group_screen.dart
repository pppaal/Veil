import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Creates a group: its name, the handles of its members (at least one
/// besides the creator), an optional description and the button, then one
/// note on what of a group is encrypted and what the relay keeps.
class StartGroupScreen extends ConsumerStatefulWidget {
  const StartGroupScreen({super.key});

  @override
  ConsumerState<StartGroupScreen> createState() => _StartGroupScreenState();
}

class _StartGroupScreenState extends ConsumerState<StartGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _membersController = TextEditingController();
  bool _creating = false;

  // Whether the last attempt of this screen failed; a failure elsewhere in
  // the messenger is not this screen's to show.
  bool _failed = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  // The handles typed, without the creator's own: whoever creates a group
  // is in it already.
  List<String> get _handles {
    final own = ref.read(appSessionProvider).handle?.toLowerCase();
    return _membersController.text
        .split(RegExp(r'[\s,]+'))
        .map((entry) => entry.trim().replaceAll(RegExp(r'^@'), ''))
        .where((entry) => entry.isNotEmpty && entry.toLowerCase() != own)
        .toList();
  }

  // A group needs someone besides its creator, and this build cannot add
  // members to a group later: one without any would stay a group of one.
  bool get _ready => _nameController.text.trim().isNotEmpty && _handles.isNotEmpty;

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (!_ready || _creating) return;
    setState(() {
      _creating = true;
      _failed = false;
    });
    final messenger = ref.read(messengerControllerProvider);
    await messenger.createGroup(
      name: name,
      description: _descriptionController.text.trim(),
      memberHandles: _handles,
    );
    if (!mounted) return;
    if (messenger.errorMessage != null) {
      setState(() {
        _creating = false;
        _failed = true;
      });
      return;
    }
    // Back to the list the screen was opened from; opened by itself (a
    // link), it has nothing under it to go back to.
    context.canPop() ? context.pop() : context.go('/conversations');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final memberCount = _handles.length;
    void edited(String _) => setState(() => _failed = false);

    return VeilShell(
      title: l10n.startGroupTitle,
      maxWidth: 560,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.lg, VeilSpace.lg, VeilSpace.xl),
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: edited,
            decoration: InputDecoration(labelText: l10n.startGroupNameInput, hintText: l10n.startGroupNameHint),
          ),
          const SizedBox(height: VeilSpace.sm),
          TextField(
            controller: _membersController,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: edited,
            decoration: InputDecoration(
              labelText: l10n.startGroupMembersInput,
              hintText: 'icarus, daedalus, minos',
              suffixText: memberCount == 0 ? null : l10n.startGroupMembersCount(memberCount),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(VeilSpace.xxs, VeilSpace.xs, VeilSpace.xxs, 0),
            child: VeilCopy(
              l10n.startGroupMembersCaption,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          TextField(
            controller: _descriptionController,
            minLines: 1,
            maxLines: 3,
            onChanged: edited,
            decoration: InputDecoration(
              labelText: l10n.startGroupDescriptionInput,
              hintText: l10n.startGroupDescriptionHint,
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilInlineBanner(
              title: l10n.startGroupErrorTitle,
              message: l10n.startGroupErrorBody,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            onPressed: _creating || !_ready ? null : _create,
            label: _creating ? l10n.startGroupCreating : l10n.startGroupCreateButton,
            icon: Icons.group_add_rounded,
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilInlineBanner(icon: Icons.lock_outline_rounded, message: l10n.startGroupNote),
        ],
      ),
    );
  }
}
