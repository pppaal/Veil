import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/contacts_providers.dart';

// The sheets of the contacts tab: adding a contact, what to do with one,
// and the name this device calls it by. Each scrolls inside the room the
// keyboard leaves, so its button stays in reach on a small phone.

/// A sheet's content above the keyboard and the system bar, scrolling when
/// the two leave it less room than it needs.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Asks for a handle and, optionally, a name for it, and adds the contact.
Future<void> showAddContactSheet(BuildContext context, WidgetRef ref) {
  VeilHaptics.selection();
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddContactSheet(
      // Said on the screen behind the sheet, once the sheet is gone.
      onAdded: (handle) {
        if (!context.mounted) return;
        VeilToast.show(context, message: l10n.contactsAdded(handle), tone: VeilBannerTone.good);
      },
    ),
  );
}

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet({required this.onAdded});

  final ValueChanged<String> onAdded;

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _handle = TextEditingController();
  final _nickname = TextEditingController();
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _handle.dispose();
    _nickname.dispose();
    super.dispose();
  }

  String get _typedHandle => _handle.text.trim().replaceAll(RegExp(r'^@'), '');

  Future<void> _save() async {
    final handle = _typedHandle;
    if (handle.isEmpty || _saving) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _failed = false;
    });
    final added = await ref.read(contactsControllerProvider).addContact(handle: handle, nickname: _nickname.text);
    if (!mounted) return;
    if (!added) {
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    navigator.pop();
    widget.onAdded(handle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return _SheetBody(
      children: [
        Text(l10n.contactsAdd, style: theme.textTheme.titleLarge),
        const SizedBox(height: VeilSpace.xxs),
        // A refusal takes the place of the instruction it repeats, so the
        // sheet keeps its height and the button stays above the keyboard.
        VeilCopy(
          _failed ? l10n.contactsAddFailed : l10n.contactsAddSheetBody,
          style: theme.textTheme.bodySmall?.copyWith(color: _failed ? palette.danger : palette.textMuted),
        ),
        const SizedBox(height: VeilSpace.md),
        TextField(
          controller: _handle,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _failed = false),
          decoration: InputDecoration(labelText: l10n.contactsHandleLabel, hintText: 'icarus', prefixText: '@'),
        ),
        const SizedBox(height: VeilSpace.sm),
        TextField(
          controller: _nickname,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: l10n.contactsNicknameLabel, hintText: l10n.contactsNicknameHint),
        ),
        const SizedBox(height: VeilSpace.md),
        VeilButton(
          label: _saving ? l10n.contactsWorking : l10n.contactsSave,
          onPressed: _saving || _typedHandle.isEmpty ? null : _save,
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilCopy(l10n.contactsNotice, style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubtle)),
      ],
    );
  }
}

/// What to do with [contact]: open the chat, rename it, remove it.
Future<void> showContactActionsSheet(BuildContext context, WidgetRef ref, ContactEntry contact) {
  VeilHaptics.medium();
  final l10n = AppLocalizations.of(context);

  Future<void> startChat() async {
    final conversationId = await ref.read(messengerControllerProvider).startConversationByHandle(contact.handle);
    if (!context.mounted) return;
    if (conversationId != null) {
      context.push('/chat/$conversationId');
    } else {
      VeilToast.show(context, message: l10n.contactsStartChatFailed, tone: VeilBannerTone.warn);
    }
  }

  Future<void> remove() async {
    final removed = await ref.read(contactsControllerProvider).removeContact(contact.handle);
    if (!context.mounted) return;
    VeilToast.show(
      context,
      message: removed ? l10n.contactsRemoved(contact.label) : l10n.contactsRemoveFailed,
      tone: removed ? VeilBannerTone.info : VeilBannerTone.warn,
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    // Three buttons under the name are taller than the half screen a sheet
    // gets by default on a small phone.
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = sheetContext.veilPalette;
      void close() => Navigator.of(sheetContext).pop();
      return _SheetBody(
        children: [
          _ContactHeader(contact: contact),
          const SizedBox(height: VeilSpace.lg),
          VeilButton(
            label: l10n.contactsStartChat,
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () {
              close();
              startChat();
            },
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            label: l10n.contactsEditNickname,
            icon: Icons.edit_outlined,
            tone: VeilButtonTone.secondary,
            onPressed: () {
              close();
              showContactNicknameSheet(context, ref, contact);
            },
          ),
          const SizedBox(height: VeilSpace.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.danger,
                side: BorderSide(color: palette.danger.withValues(alpha: 0.45)),
              ),
              onPressed: () {
                VeilHaptics.medium();
                close();
                remove();
              },
              icon: const Icon(Icons.person_remove_outlined, size: VeilIconSize.sm),
              label: Text(l10n.contactsRemove),
            ),
          ),
        ],
      );
    },
  );
}

/// Changes the name this device calls [contact] by. The relay never sees it.
Future<void> showContactNicknameSheet(BuildContext context, WidgetRef ref, ContactEntry contact) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NicknameSheet(contact: contact),
  );
}

class _NicknameSheet extends ConsumerStatefulWidget {
  const _NicknameSheet({required this.contact});

  final ContactEntry contact;

  @override
  ConsumerState<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends ConsumerState<_NicknameSheet> {
  late final _nickname = TextEditingController(text: widget.contact.nickname ?? '');

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await ref.read(contactsControllerProvider).renameContact(widget.contact.handle, _nickname.text);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return _SheetBody(
      children: [
        _ContactHeader(contact: widget.contact),
        const SizedBox(height: VeilSpace.md),
        TextField(
          controller: _nickname,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: l10n.contactsNicknameLabel, hintText: l10n.contactsNicknameHint),
        ),
        const SizedBox(height: VeilSpace.xs),
        VeilCopy(l10n.contactsNicknameCaption, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
        const SizedBox(height: VeilSpace.md),
        VeilButton(label: l10n.contactsSaveNickname, onPressed: _save),
      ],
    );
  }
}

/// Who a sheet is about: the name this device shows and the handle.
class _ContactHeader extends StatelessWidget {
  const _ContactHeader({required this.contact});

  final ContactEntry contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.primarySoft,
            border: Border.all(color: palette.stroke),
          ),
          child: Text(
            contact.label.characters.firstOrNull?.toUpperCase() ?? '#',
            style: theme.textTheme.titleMedium?.copyWith(color: palette.primary),
          ),
        ),
        const SizedBox(width: VeilSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contact.label, style: theme.textTheme.titleMedium),
              Text('@${contact.handle}', style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubtle)),
            ],
          ),
        ),
      ],
    );
  }
}
