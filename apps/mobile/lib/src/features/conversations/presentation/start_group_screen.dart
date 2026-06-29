import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class StartGroupScreen extends ConsumerStatefulWidget {
  const StartGroupScreen({super.key});

  @override
  ConsumerState<StartGroupScreen> createState() => _StartGroupScreenState();
}

class _StartGroupScreenState extends ConsumerState<StartGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _membersController = TextEditingController();
  bool _isPublic = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  List<String> _parseHandles(String raw) {
    return raw
        .split(RegExp(r'[\s,]+'))
        .map((entry) => entry.trim().replaceAll(RegExp(r'^@'), ''))
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(messengerControllerProvider);
    final l10n = AppLocalizations.of(context);
    final trimmedName = _nameController.text.trim();
    final parsedHandles = _parseHandles(_membersController.text);

    return VeilShell(
      title: l10n.startGroupTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.startGroupEyebrow,
            title: l10n.startGroupHeroTitle,
            body: l10n.startGroupHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.startGroupPillInviteOnly),
                VeilStatusPill(label: l10n.startGroupPillManualRoster),
                VeilStatusPill(label: l10n.startGroupPillE2E),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.startGroupNameLabel,
            trailing: trimmedName.isEmpty
                ? VeilStatusPill(label: l10n.startGroupRequired, tone: VeilBannerTone.warn)
                : VeilStatusPill(label: trimmedName),
            caption: l10n.startGroupNameCaption,
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.startGroupNameInput,
                hintText: 'Signal Boost',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.startGroupDescriptionLabel,
            caption: l10n.startGroupDescriptionCaption,
            child: TextField(
              controller: _descriptionController,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.startGroupDescriptionInput,
                hintText: l10n.startGroupDescriptionHint,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: l10n.startGroupMembersLabel,
            trailing: parsedHandles.isEmpty
                ? VeilStatusPill(label: l10n.startGroupNoneYet, tone: VeilBannerTone.warn)
                : VeilStatusPill(label: l10n.startGroupMembersCount(parsedHandles.length)),
            caption: l10n.startGroupMembersCaption,
            child: TextField(
              controller: _membersController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.startGroupMembersInput,
                hintText: 'icarus, daedalus, minos',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          SwitchListTile(
            value: _isPublic,
            onChanged: (value) => setState(() => _isPublic = value),
            title: Text(l10n.startGroupPublicTitle),
            subtitle: Text(l10n.startGroupPublicSubtitle),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: l10n.startGroupErrorTitle,
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
            onPressed: controller.isBusy || trimmedName.isEmpty
                ? null
                : () async {
                    await ref.read(messengerControllerProvider).createGroup(
                          name: trimmedName,
                          description: _descriptionController.text.trim(),
                          memberHandles: parsedHandles,
                          isPublic: _isPublic,
                        );
                    if (context.mounted &&
                        ref.read(messengerControllerProvider).errorMessage == null) {
                      context.pop();
                    }
                  },
            label: controller.isBusy ? l10n.startGroupCreating : l10n.startGroupCreateButton,
            icon: Icons.group_add_rounded,
          ),
        ],
      ),
    );
  }
}
