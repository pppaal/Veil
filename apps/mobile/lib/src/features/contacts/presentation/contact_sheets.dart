import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../safety/application/safety_accounts.dart';
import '../../safety/data/abuse_reports.dart';
import '../../safety/data/safety_providers.dart';
import '../../safety/presentation/block_actions.dart';
import '../../safety/presentation/report_sheet.dart';
import '../data/contacts_providers.dart';

// The sheets of the contacts tab: adding a contact, what to do with one,
// and the name this phone calls it by. Each scrolls inside the room the
// keyboard leaves, so its button stays in reach on a small phone.

/// Opens a sheet of the contacts tab, with the drag handle every sheet has,
/// over the tab bar like any sheet.
Future<void> _showSheet(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      // A sheet with a field grows above the keyboard, and three rows under a
      // header are taller than the half screen a sheet gets by default; it
      // stops under the status bar.
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: builder,
    );

/// A sheet's content above the keyboard and the system bar, scrolling when
/// the two leave it less room than it needs. Rows run full-bleed; the rest
/// keeps the 16 side gutter ([_padded]).
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: VeilSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// The 16 side gutter of what is not a row: a title, a field, a button.
Widget _padded(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md), child: child);

/// Asks for a handle and, optionally, a name for it, and adds the contact.
Future<void> showAddContactSheet(BuildContext context, WidgetRef ref) {
  VeilHaptics.selection();
  final l10n = AppLocalizations.of(context);
  return _showSheet(
    context,
    (_) => _AddContactSheet(
      // Said on the screen behind the sheet, once the sheet is gone.
      onAdded: (handle) {
        if (!context.mounted) return;
        showVeilToast(context, l10n.contactsAdded(handle), tone: VeilTone.good);
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
        _padded(Text(l10n.contactsAdd, style: theme.textTheme.titleLarge)),
        const SizedBox(height: VeilSpace.md),
        // A refusal takes the place of the instruction under the field, so
        // the sheet keeps its height and the button stays above the keyboard.
        _padded(TextField(
          controller: _handle,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _failed = false),
          decoration: InputDecoration(
            labelText: l10n.contactsHandleLabel,
            hintText: l10n.contactsHandleHint,
            prefixText: '@',
            helperText: l10n.contactsAddSheetBody,
            errorText: _failed ? l10n.contactsAddFailed : null,
            helperMaxLines: 2,
            errorMaxLines: 2,
          ),
        )),
        const SizedBox(height: VeilSpace.sm),
        _padded(TextField(
          controller: _nickname,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          // Who sees it is said once, under the button.
          decoration: InputDecoration(labelText: l10n.contactsNicknameLabel),
        )),
        const SizedBox(height: VeilSpace.md),
        _padded(VeilButton(
          label: _saving ? l10n.contactsWorking : l10n.contactsSave,
          onPressed: _saving || _typedHandle.isEmpty ? null : _save,
        )),
        const SizedBox(height: VeilSpace.sm),
        // What the server learns of the list, said where one adds to it.
        _padded(Text(l10n.contactsNotice, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted))),
      ],
    );
  }
}

/// What to do with [contact]: open the chat, rename it, report or block
/// them, remove it.
Future<void> showContactActionsSheet(BuildContext context, WidgetRef ref, ContactEntry contact) {
  VeilHaptics.medium();
  final l10n = AppLocalizations.of(context);
  final blocked = ref.read(blockedAccountsProvider).byHandle(contact.handle);

  // Blocking and reporting need their account, which the contact list does
  // not hold (see SafetyAccounts.accountIdFor).
  Future<String?> account() async {
    final userId = await ref.read(safetyAccountsProvider).accountIdFor(contact.handle);
    if (userId == null && context.mounted) {
      showVeilToast(context, l10n.safetyAccountNotFound(contact.handle), tone: VeilTone.warn);
    }
    return userId;
  }

  Future<void> report() async {
    final userId = await account();
    if (userId == null || !context.mounted) return;
    await showReportSheet(context, ref, ReportTarget(userId: userId, handle: contact.handle, offerBlock: true));
  }

  Future<void> block() async {
    final userId = await account();
    if (userId == null || !context.mounted) return;
    await confirmAndBlock(context, ref, userId: userId, handle: contact.handle, announce: true);
  }

  Future<void> startChat() async {
    final conversationId = await ref.read(messengerControllerProvider).startConversationByHandle(contact.handle);
    if (!context.mounted) return;
    if (conversationId != null) {
      context.push('/chat/$conversationId');
    } else {
      showVeilToast(context, l10n.contactsStartChatFailed, tone: VeilTone.warn);
    }
  }

  Future<void> remove() async {
    final removed = await ref.read(contactsControllerProvider).removeContact(contact.handle);
    if (!context.mounted) return;
    showVeilToast(
      context,
      removed ? l10n.contactsRemoved(contact.label) : l10n.contactsRemoveFailed,
      tone: removed ? VeilTone.info : VeilTone.warn,
    );
  }

  return _showSheet(context, (sheetContext) {
    void close() => Navigator.of(sheetContext).pop();
    // Each row does what it says at once: none leads to a screen of its own.
    const noChevron = SizedBox.shrink();
    return _SheetBody(
      children: [
        _ContactHeader(contact: contact),
        const SizedBox(height: VeilSpace.xs),
        VeilGroup(
          children: [
            VeilRow(
              title: l10n.contactsStartChat,
              trailing: noChevron,
              onTap: () {
                close();
                startChat();
              },
            ),
            VeilRow(
              title: l10n.contactsEditNickname,
              trailing: noChevron,
              onTap: () {
                close();
                showContactNicknameSheet(context, ref, contact);
              },
            ),
            VeilRow(
              key: const ValueKey('contact-report'),
              title: l10n.reportAction,
              trailing: noChevron,
              onTap: () {
                close();
                report();
              },
            ),
            if (blocked != null)
              VeilRow(
                key: const ValueKey('contact-unblock'),
                title: l10n.unblockAction,
                trailing: noChevron,
                onTap: () {
                  close();
                  unblockAccount(context, ref, userId: blocked.userId, handle: contact.handle, announce: true);
                },
              )
            else
              VeilRow(
                key: const ValueKey('contact-block'),
                title: l10n.blockAction,
                destructive: true,
                onTap: () {
                  close();
                  block();
                },
              ),
            VeilRow(
              title: l10n.contactsRemove,
              destructive: true,
              onTap: () {
                close();
                remove();
              },
            ),
          ],
        ),
      ],
    );
  });
}

/// Changes the name this phone calls [contact] by. The server never sees it.
Future<void> showContactNicknameSheet(BuildContext context, WidgetRef ref, ContactEntry contact) {
  return _showSheet(context, (_) => _NicknameSheet(contact: contact));
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
    return _SheetBody(
      children: [
        _ContactHeader(contact: widget.contact),
        const SizedBox(height: VeilSpace.md),
        _padded(TextField(
          controller: _nickname,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: l10n.contactsNicknameLabel,
            helperText: l10n.contactsNicknameCaption,
            helperMaxLines: 2,
          ),
        )),
        const SizedBox(height: VeilSpace.md),
        _padded(VeilButton(label: l10n.contactsSaveNickname, onPressed: _save)),
      ],
    );
  }
}

/// Who a sheet is about: the avatar, the name this phone shows and the
/// handle.
class _ContactHeader extends StatelessWidget {
  const _ContactHeader({required this.contact});

  final ContactEntry contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return _padded(Row(
      children: [
        VeilAvatar(name: contact.label, seed: contact.handle, size: 56),
        const SizedBox(width: VeilSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A name and a handle are their owner's words: drawn as typed.
              Text(contact.label, style: theme.textTheme.titleLarge),
              Text('@${contact.handle}', style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
            ],
          ),
        ),
      ],
    ));
  }
}
