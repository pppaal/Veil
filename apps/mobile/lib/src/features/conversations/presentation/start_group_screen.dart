import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
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
    final trimmedName = _nameController.text.trim();
    final parsedHandles = _parseHandles(_membersController.text);

    return VeilShell(
      title: 'Start Group Chat',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'GROUP CREATION',
            title: 'Private by invitation.',
            body:
                'Groups are explicit. Add members by handle — VEIL never expands invites through contact graphs.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'Invite-only'),
                VeilStatusPill(label: 'Manual roster'),
                VeilStatusPill(label: 'E2E encrypted'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: 'GROUP NAME',
            trailing: trimmedName.isEmpty
                ? const VeilStatusPill(label: 'Required', tone: VeilBannerTone.warn)
                : VeilStatusPill(label: trimmedName),
            caption: 'Visible to members. You can rename later.',
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Signal Boost',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: 'DESCRIPTION',
            caption: 'Optional. Purpose, charter, or context for members.',
            child: TextField(
              controller: _descriptionController,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What is this group for?',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilFieldBlock(
            label: 'INITIAL MEMBERS',
            trailing: parsedHandles.isEmpty
                ? const VeilStatusPill(label: 'None yet', tone: VeilBannerTone.warn)
                : VeilStatusPill(label: '${parsedHandles.length} handle(s)'),
            caption: 'Comma or space separated handles. You can add more after creation.',
            child: TextField(
              controller: _membersController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Member handles',
                hintText: 'icarus, daedalus, minos',
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          SwitchListTile(
            value: _isPublic,
            onChanged: (value) => setState(() => _isPublic = value),
            title: const Text('Public directory'),
            subtitle: const Text(
              'Public groups are discoverable by handle. Keep off for invite-only groups.',
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Unable to create group',
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
            label: controller.isBusy ? 'Creating group' : 'Create group',
            icon: Icons.group_add_rounded,
          ),
        ],
      ),
    );
  }
}
