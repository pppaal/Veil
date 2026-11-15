import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/contact_index.dart';
import '../data/contacts_providers.dart';
import 'contact_sheets.dart';

/// The contacts tab: the list is the screen. Search leads it and scrolls
/// away with it, adding a contact is an action of the bar, and what the
/// relay keeps of the list is said under it.
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(contactsControllerProvider);
    final searching = _searchController.text.trim().isNotEmpty;
    final sections = sectionContacts(
      filterContacts(controller.contacts, _searchController.text),
      hangulFirst: l10n.localeName == 'ko',
    );
    const sides = EdgeInsets.symmetric(horizontal: VeilSpace.sm);

    return VeilShell(
      title: l10n.navContacts,
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: l10n.contactsAdd,
          onPressed: controller.isMutating ? null : () => showAddContactSheet(context, ref),
          icon: const Icon(Icons.person_add_outlined),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.xs, VeilSpace.sm, 0),
              sliver: SliverList.list(
                children: [
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm + 2),
                      hintText: l10n.contactsSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: !searching
                          ? null
                          : IconButton(
                              tooltip: l10n.contactsSearchClear,
                              style: IconButton.styleFrom(backgroundColor: Colors.transparent),
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  if (controller.loadFailed) ...[
                    const SizedBox(height: VeilSpace.xs),
                    VeilInlineBanner(
                      dense: true,
                      title: l10n.contactsErrorTitle,
                      message: l10n.contactsErrorBody,
                      tone: VeilBannerTone.danger,
                      actionLabel: l10n.commonRetry,
                      onAction: controller.refresh,
                    ),
                  ],
                ],
              ),
            ),
            if (controller.isLoading && controller.contacts.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.only(top: VeilSpace.xxl),
                sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
              )
            else if (sections.isEmpty)
              SliverToBoxAdapter(
                child: VeilEmptyState(
                  title: searching ? l10n.contactsEmptySearchTitle : l10n.contactsEmptyTitle,
                  body: searching ? l10n.contactsEmptySearchBody : l10n.contactsEmptyBody,
                  icon: searching ? Icons.search_off_rounded : Icons.people_outline_rounded,
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
                padding: sides,
                sliver: SliverList.builder(
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          key: ValueKey('contacts-index-${section.letter}'),
                          padding: const EdgeInsets.fromLTRB(VeilSpace.xs, VeilSpace.sm, VeilSpace.xs, VeilSpace.xxs),
                          child: Semantics(
                            header: true,
                            child: Text(
                              section.letter,
                              style: theme.textTheme.labelMedium?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        ),
                        for (final contact in section.contacts)
                          VeilConversationCard(
                            dense: true,
                            title: contact.label,
                            handle: contact.handle,
                            subtitle: '@${contact.handle}',
                            timestamp: '',
                            semanticLabel: l10n.contactsRowSemantics(contact.label),
                            onTap: () => showContactActionsSheet(context, ref, contact),
                          ),
                      ],
                    );
                  },
                ),
              ),
            // What the relay learns of this list, and what it does not.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.lg),
              sliver: SliverToBoxAdapter(
                child: VeilCopy(
                  l10n.contactsNotice,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
