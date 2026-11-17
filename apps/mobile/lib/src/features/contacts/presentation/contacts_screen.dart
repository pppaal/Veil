import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/contact_index.dart';
import '../data/contacts_providers.dart';
import 'contact_sheets.dart';

/// The contacts tab: the list is the screen, one run of names in order
/// with no letter headers (Telegram). Search leads it and scrolls away with
/// it, and adding a contact is an action of the bar.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(contactsControllerProvider);
    final searching = _searchController.text.trim().isNotEmpty;
    final contacts = [
      for (final section in sectionContacts(filterContacts(controller.contacts, _searchController.text)))
        ...section.contacts,
    ];

    return VeilShell(
      title: l10n.navContacts,
      actions: [
        IconButton(
          tooltip: l10n.contactsAdd,
          onPressed: controller.isMutating ? null : () => showAddContactSheet(context, ref),
          icon: const Icon(Icons.person_add_alt_1_outlined),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, VeilSpace.xxs),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.contactsSearchHint,
                    prefixIcon: Icon(Icons.search, color: palette.textMuted),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    suffixIcon: !searching
                        ? null
                        : IconButton(
                            tooltip: l10n.contactsSearchClear,
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close, size: 20),
                          ),
                  ),
                ),
              ),
            ),
            // Only while the last load failed: one line and Retry over the
            // list that loaded before.
            if (controller.loadFailed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: VeilSpace.md, end: VeilSpace.xxs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.contactsErrorTitle,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                        ),
                      ),
                      VeilButton(
                        expanded: false,
                        tone: VeilButtonTone.ghost,
                        label: l10n.commonRetry,
                        onPressed: controller.refresh,
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.isLoading && controller.contacts.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.only(top: VeilSpace.xxl),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              )
            else if (contacts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: VeilEmptyState(
                  title: searching ? l10n.contactsEmptySearchTitle : l10n.contactsEmptyTitle,
                  action: searching
                      ? null
                      : VeilButton(
                          expanded: false,
                          tone: VeilButtonTone.secondary,
                          label: l10n.contactsAdd,
                          onPressed: () => showAddContactSheet(context, ref),
                        ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: VeilSpace.xs, bottom: VeilSpace.lg),
                sliver: SliverToBoxAdapter(
                  child: VeilGroup(
                    key: const ValueKey('contacts-list'),
                    inset: ContactRow.textInset,
                    children: [
                      for (final contact in contacts)
                        ContactRow(
                          key: ValueKey('contact-${contact.handle}'),
                          contact: contact,
                          onTap: () => showContactActionsSheet(context, ref, contact),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One contact: the avatar, the name this phone shows and the handle. A
/// screen reader hears "Contact" and the name.
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.contact, this.onTap});

  final ContactEntry contact;
  final VoidCallback? onTap;

  /// Where the text starts, and the hairlines between rows with it: the
  /// 16 side gutter, the 40 avatar and the 12 gap after it.
  static const double textInset = 68;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      label: l10n.contactsRowSemantics(contact.title),
      onTap: onTap,
      excludeSemantics: true,
      child: VeilRow(
        leading: VeilAvatar(name: contact.label, seed: contact.handle),
        // A name and a handle are their owner's words: drawn as typed.
        title: contact.title,
        subtitle: contact.handleLine,
        trailing: const SizedBox.shrink(),
        onTap: onTap,
      ),
    );
  }
}
