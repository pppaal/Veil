import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../safety/application/safety_accounts.dart';
import '../../safety/data/safety_providers.dart';

/// Creates a group: its name, an optional description, its members (each
/// handle a chip once a space, a comma or Return ends it) with the one rule
/// under them, the button, then one plain line on what of a group the
/// server can read.
class StartGroupScreen extends ConsumerStatefulWidget {
  const StartGroupScreen({super.key});

  @override
  ConsumerState<StartGroupScreen> createState() => _StartGroupScreenState();
}

final _separators = RegExp(r'[\s,]+');

class _StartGroupScreenState extends ConsumerState<StartGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _membersController = TextEditingController();
  final _membersFocus = FocusNode();
  final List<String> _members = [];
  bool _creating = false;

  // Why the last attempt failed: a handle the server does not know (its
  // chip is red), or anything else.
  String? _notFound;
  bool _failed = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _membersController.dispose();
    _membersFocus.dispose();
    super.dispose();
  }

  String? get _ownHandle => ref.read(appSessionProvider).handle?.toLowerCase();

  static String _clean(String entry) => entry.trim().replaceAll(RegExp(r'^@'), '').toLowerCase();

  // Turns what was typed into chips: every handle a separator ended, or all
  // of it when [all]. The creator is in the group already and gets none.
  void _commit({bool all = false}) {
    final text = _membersController.text;
    final parts = text.split(_separators);
    final rest = all || _separators.hasMatch(text.isEmpty ? '' : text[text.length - 1]) ? '' : parts.removeLast();
    var changed = false;
    for (final part in parts) {
      final handle = _clean(part);
      if (handle.isEmpty || handle == _ownHandle || _members.contains(handle)) continue;
      _members.add(handle);
      changed = true;
    }
    if (changed || rest != text) {
      _membersController.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
    }
    setState(() {
      _failed = false;
      _notFound = null;
    });
  }

  // The members: the chips, and a handle still being typed.
  List<String> get _handles {
    final typing = _clean(_membersController.text);
    return [..._members, if (typing.isNotEmpty && typing != _ownHandle && !_members.contains(typing)) typing];
  }

  // A group needs someone besides its creator, and this build cannot add
  // members to a group later: one without any would stay a group of one.
  bool get _ready => _nameController.text.trim().isNotEmpty && _handles.isNotEmpty;

  Future<void> _create() async {
    if (!_ready || _creating) return;
    _commit(all: true);
    final name = _nameController.text.trim();
    final handles = List<String>.of(_members);
    setState(() {
      _creating = true;
      _failed = false;
      _notFound = null;
    });
    final messenger = ref.read(messengerControllerProvider);
    final trust = ref.read(contactTrustProvider);
    final created = await messenger.createGroup(
      name: name,
      description: _descriptionController.text.trim(),
      memberHandles: handles,
    );
    // Only the id the relay answered with is the user's own group: never a
    // message request. A stranger's group listed meanwhile stays one.
    if (created != null) await trust.acceptCreated(created);
    if (!mounted) return;
    if (messenger.errorMessage != null) {
      // The server names no handle it could not find: each is looked up
      // to find the one.
      String? missing;
      if (messenger.failedAsNotFound) {
        final accounts = ref.read(safetyAccountsProvider);
        for (final handle in handles) {
          if (await accounts.accountIdFor(handle) == null) {
            missing = handle;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _creating = false;
        _notFound = missing;
        _failed = missing == null;
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
    final palette = context.veilPalette;
    final memberCount = _handles.length;
    void edited(String _) => setState(() {
          _failed = false;
          _notFound = null;
        });
    final String? membersError = _notFound != null
        ? l10n.safetyAccountNotFound(_notFound!)
        : _failed
            ? l10n.startGroupMembersError
            : null;

    return VeilShell(
      title: l10n.startGroupTitle,
      maxWidth: 560,
      child: ListView(
        padding: VeilShell.formPadding,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: edited,
            decoration: InputDecoration(labelText: l10n.startGroupNameInput),
          ),
          const SizedBox(height: VeilSpace.sm),
          TextField(
            controller: _descriptionController,
            minLines: 1,
            maxLines: 3,
            onChanged: edited,
            decoration: InputDecoration(labelText: l10n.startGroupDescriptionInput),
          ),
          const SizedBox(height: VeilSpace.md),
          if (_members.isNotEmpty) ...[
            Wrap(
              spacing: VeilSpace.xs,
              runSpacing: VeilSpace.xs,
              children: [
                for (final handle in _members)
                  InputChip(
                    key: ValueKey('group-member-$handle'),
                    label: Text('@$handle'),
                    labelStyle: handle == _notFound ? TextStyle(color: palette.danger) : null,
                    side: handle == _notFound ? BorderSide(color: palette.danger) : null,
                    onDeleted: _creating
                        ? null
                        : () => setState(() {
                              _members.remove(handle);
                              if (_notFound == handle) _notFound = null;
                            }),
                  ),
              ],
            ),
            const SizedBox(height: VeilSpace.xs),
          ],
          TextField(
            controller: _membersController,
            focusNode: _membersFocus,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (text) {
              if (_separators.hasMatch(text)) {
                _commit();
              } else {
                edited(text);
              }
            },
            onSubmitted: (_) {
              _commit(all: true);
              _membersFocus.requestFocus();
            },
            decoration: InputDecoration(
              labelText: l10n.startGroupMembersInput,
              hintText: l10n.startGroupMembersHint,
              suffixText: memberCount == 0 ? null : l10n.startGroupMembersCount(memberCount),
              helperText: l10n.startGroupMembersCaption,
              errorText: membersError,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            onPressed: _creating || !_ready ? null : _create,
            label: _creating ? l10n.startGroupCreating : l10n.startGroupCreateButton,
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(
            l10n.startGroupNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
