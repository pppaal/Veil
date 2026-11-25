import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/identity/issued_handle.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../contacts/data/contact_index.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../safety/data/safety_providers.dart';
import 'conversation_list_logic.dart';

/// The compose screen: a search field, then "New group" and "One-time link",
/// then the contacts, which the field filters. A typed handle that is no
/// contact's becomes the first row, "Chat with @sam". A tap on a row, or Go
/// on the keyboard for the first one, opens the chat.
class StartDirectChatScreen extends ConsumerStatefulWidget {
  const StartDirectChatScreen({super.key});

  @override
  ConsumerState<StartDirectChatScreen> createState() => _StartDirectChatScreenState();
}

class _StartDirectChatScreenState extends ConsumerState<StartDirectChatScreen> {
  final _queryController = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String get _query => _queryController.text.trim();

  // What was typed, as a handle: without its @, in the case handles have.
  String get _typedHandle => _query.replaceAll(RegExp(r'^@'), '').toLowerCase();

  Future<void> _open(String handle) async {
    if (handle.isEmpty || _opening) return;
    setState(() => _opening = true);
    final messenger = ref.read(messengerControllerProvider);
    // A chat opened from a handle the user typed is theirs: accepted, and
    // started by them, so it is never a message request.
    final conversationId = await ref.read(contactTrustProvider).startDirect(handle);
    if (!mounted) return;
    if (conversationId == null) {
      setState(() => _opening = false);
      final l10n = AppLocalizations.of(context);
      showVeilToast(
        context,
        messenger.failedAsNotFound ? l10n.safetyAccountNotFound(handle) : l10n.startDirectHandleError,
      );
      return;
    }
    // Beside the list the new conversation is already on screen; on a phone
    // it opens in this screen's place.
    if (shouldUseWideConversationLayout(MediaQuery.sizeOf(context).width)) {
      context.pop();
    } else {
      context.pushReplacement('/chat/$conversationId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final contacts = ref.watch(contactsControllerProvider).contacts;
    final matches = [
      for (final section in sectionContacts(filterContacts(contacts, _query.replaceAll(RegExp(r'^@'), ''))))
        ...section.contacts,
    ];
    final handle = _typedHandle;
    final offerHandle = isIssuableHandle(handle) && !contacts.any((contact) => contact.handle == handle);
    // A contact the text matches comes before a stranger with that handle:
    // "sam" for Sam Rivera (@samr) must not open a chat with someone else
    // who happens to be @sam. The handle's row then follows the contacts,
    // so the keyboard's Go opens the first row, whichever it is.
    final handleFirst = offerHandle && matches.isEmpty;
    final first = matches.where((contact) => contact.handle == handle).firstOrNull?.handle ??
        matches.firstOrNull?.handle ??
        (offerHandle ? handle : null);
    final chatWithHandle = VeilRow(
      key: const ValueKey('start-chat-with-handle'),
      leading: Icon(Icons.chat_bubble_outline, color: palette.textMuted),
      title: _opening ? l10n.startDirectOpening : l10n.startDirectChatWith(handle),
      trailing: const SizedBox.shrink(),
      onTap: _opening ? null : () => _open(handle),
    );

    return VeilShell(
      title: l10n.startDirectTitle,
      maxWidth: 560,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, VeilSpace.xs),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_opening,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (first != null) _open(first);
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.startDirectHandleHint,
                prefixIcon: Icon(Icons.search, color: palette.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ),
          ),
          VeilGroup(
            inset: 56,
            children: [
              if (handleFirst) chatWithHandle,
              if (_query.isEmpty) ...[
                VeilRow(
                  key: const ValueKey('start-new-group'),
                  leading: Icon(Icons.group_add_outlined, color: palette.textMuted),
                  title: l10n.conversationsNewGroup,
                  trailing: const SizedBox.shrink(),
                  onTap: () => context.pushReplacement('/start-group'),
                ),
                VeilRow(
                  key: const ValueKey('start-one-time-link'),
                  leading: Icon(Icons.link, color: palette.textMuted),
                  title: l10n.oneTimeLinkTitle,
                  trailing: const SizedBox.shrink(),
                  onTap: () => context.pushReplacement('/secret-link'),
                ),
              ],
            ],
          ),
          if (matches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.md, VeilSpace.md, 6),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.startDirectContactsHeader,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ),
            ),
            VeilGroup(
              inset: 68,
              children: [
                for (final contact in matches)
                  VeilRow(
                    key: ValueKey('start-contact-${contact.handle}'),
                    leading: VeilAvatar(name: contact.label, seed: contact.handle),
                    // A name and a handle are their owner's words: drawn as typed.
                    title: contact.title,
                    subtitle: contact.handleLine,
                    trailing: const SizedBox.shrink(),
                    onTap: _opening ? null : () => _open(contact.handle),
                  ),
              ],
            ),
            if (offerHandle) ...[
              const SizedBox(height: VeilSpace.md),
              VeilGroup(inset: 56, children: [chatWithHandle]),
            ],
          ],
        ],
      ),
    );
  }
}
