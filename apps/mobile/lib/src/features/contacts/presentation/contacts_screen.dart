import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../../app/app_state.dart';
import '../data/contacts_providers.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ContactEntry> _filterContacts(List<ContactEntry> source) {
    if (_searchQuery.isEmpty) return source;
    return source.where((contact) {
      final label = contact.label.toLowerCase();
      final handle = contact.handle.toLowerCase();
      return label.contains(_searchQuery) || handle.contains(_searchQuery);
    }).toList();
  }

  Map<String, List<ContactEntry>> _groupByLetter(List<ContactEntry> contacts) {
    final map = <String, List<ContactEntry>>{};
    for (final contact in contacts) {
      final source = contact.label;
      final letter = source.isEmpty
          ? '#'
          : source.characters.first.toUpperCase();
      map.putIfAbsent(letter, () => []).add(contact);
    }
    for (final entries in map.values) {
      entries.sort((a, b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    }
    return map;
  }

  Future<void> _showAddContactSheet() async {
    VeilHaptics.selection();
    final handleController = TextEditingController();
    final nicknameController = TextEditingController();
    final palette = context.veilPalette;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add contact',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: VeilSpace.xs),
                  Text(
                    'Enter the exact handle. VEIL does not scan address books.',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: palette.textSubtle,
                        ),
                  ),
                  const SizedBox(height: VeilSpace.lg),
                  TextField(
                    controller: handleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Handle',
                      hintText: 'icarus',
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: VeilSpace.md),
                  TextField(
                    controller: nicknameController,
                    decoration: const InputDecoration(
                      labelText: 'Nickname (optional)',
                      hintText: 'Private label',
                    ),
                  ),
                  const SizedBox(height: VeilSpace.xl),
                  VeilButton(
                    label: 'Save contact',
                    icon: Icons.person_add_alt_1_outlined,
                    tone: VeilButtonTone.primary,
                    onPressed: () async {
                      final handle =
                          handleController.text.trim().replaceAll(
                        RegExp(r'^@'),
                        '',
                      );
                      if (handle.isEmpty) return;
                      final success = await ref
                          .read(contactsControllerProvider)
                          .addContact(
                            handle: handle,
                            nickname: nicknameController.text,
                          );
                      if (!sheetContext.mounted) return;
                      if (success) {
                        Navigator.of(sheetContext).pop();
                        if (mounted) {
                          VeilToast.show(
                            context,
                            message: 'Contact @$handle added',
                            tone: VeilBannerTone.good,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    handleController.dispose();
    nicknameController.dispose();
  }

  void _showContactActions(ContactEntry contact) {
    VeilHaptics.medium();
    final palette = context.veilPalette;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(VeilSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                        contact.label.characters.first.toUpperCase(),
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: palette.primary),
                      ),
                    ),
                    const SizedBox(width: VeilSpace.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.label,
                          style:
                              Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                        Text(
                          '@${contact.handle}',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: palette.textSubtle),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: VeilSpace.xl),
                VeilActionCluster(
                  children: [
                    VeilButton(
                      label: 'Start chat',
                      icon: Icons.chat_bubble_outline_rounded,
                      tone: VeilButtonTone.primary,
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        final conversationId = await ref
                            .read(messengerControllerProvider)
                            .startConversationByHandle(contact.handle);
                        if (!mounted) return;
                        if (conversationId != null) {
                          context.push('/chat/$conversationId');
                        } else {
                          VeilToast.show(
                            context,
                            message: 'Could not start conversation',
                            tone: VeilBannerTone.warn,
                          );
                        }
                      },
                    ),
                    VeilButton(
                      label: 'View profile',
                      icon: Icons.person_outline_rounded,
                      tone: VeilButtonTone.secondary,
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _showPublicProfile(contact);
                      },
                    ),
                    VeilButton(
                      label: 'Remove contact',
                      icon: Icons.person_remove_outlined,
                      tone: VeilButtonTone.destructive,
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        final success = await ref
                            .read(contactsControllerProvider)
                            .removeContact(contact.handle);
                        if (!mounted) return;
                        VeilToast.show(
                          context,
                          message: success
                              ? '${contact.label} removed from contacts'
                              : 'Could not remove contact',
                          tone: success
                              ? VeilBannerTone.danger
                              : VeilBannerTone.warn,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final controller = ref.watch(contactsControllerProvider);
    final contacts = _filterContacts(controller.contacts);
    final grouped = _groupByLetter(contacts);
    final letters = grouped.keys.toList()..sort();

    return VeilShell(
      title: 'Contacts',
      child: Column(
        children: [
          const VeilInlineBanner(
            message:
                'Contacts are stored on this device only. The relay does not maintain a contact list.',
            icon: Icons.devices_rounded,
          ),
          const SizedBox(height: VeilSpace.lg),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts\u2026',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: 'Clear search',
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            label: controller.isMutating ? 'Working\u2026' : 'Add contact',
            icon: Icons.person_add_outlined,
            tone: VeilButtonTone.secondary,
            onPressed: controller.isMutating ? null : _showAddContactSheet,
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Contacts error',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.lg),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => controller.refresh(),
              child: controller.isLoading && controller.contacts.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: VeilSpace.xl),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : contacts.isEmpty
                      ? ListView(
                          children: [
                            VeilEmptyState(
                              title: 'No contacts found',
                              body: _searchQuery.isNotEmpty
                                  ? 'No contacts match your search.'
                                  : 'Add contacts to start messaging securely.',
                              icon: Icons.people_outline_rounded,
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: letters.length,
                          itemBuilder: (context, sectionIndex) {
                            final letter = letters[sectionIndex];
                            final sectionContacts = grouped[letter]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: VeilSpace.md,
                                    bottom: VeilSpace.xs,
                                  ),
                                  child: Text(
                                    letter,
                                    style: theme.textTheme.labelLarge
                                        ?.copyWith(
                                      color: palette.textSubtle,
                                    ),
                                  ),
                                ),
                                ...sectionContacts.map((contact) {
                                  final glyph = contact.label.isEmpty
                                      ? '#'
                                      : contact.label.characters.first
                                          .toUpperCase();
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: VeilSpace.sm,
                                    ),
                                    child: VeilListTileCard(
                                      title: contact.label,
                                      subtitle: '@${contact.handle}',
                                      leading: Container(
                                        width: 44,
                                        height: 44,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: palette.primarySoft,
                                          border: Border.all(
                                            color: palette.stroke,
                                          ),
                                        ),
                                        child: Text(
                                          glyph,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: palette.primary,
                                          ),
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.more_horiz_rounded,
                                        color: palette.textSubtle,
                                      ),
                                      onTap: () =>
                                          _showContactActions(contact),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPublicProfile(ContactEntry contact) async {
    final profile = await ref
        .read(contactsControllerProvider)
        .fetchPublicProfile(contact.handle);
    if (!mounted) return;

    final palette = context.veilPalette;
    final displayName =
        (profile?['displayName'] as String?) ?? contact.displayName;
    final bio = profile?['bio'] as String?;
    final statusMessage = profile?['statusMessage'] as String?;
    final statusEmoji = profile?['statusEmoji'] as String?;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(VeilSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: palette.surfaceAlt,
                      child: Text(
                        (displayName ?? contact.handle)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: VeilSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName ?? contact.handle,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '@${contact.handle}',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (statusMessage != null && statusMessage.isNotEmpty) ...[
                  const SizedBox(height: VeilSpace.md),
                  Row(
                    children: [
                      if (statusEmoji != null && statusEmoji.isNotEmpty) ...[
                        Text(statusEmoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: VeilSpace.xs),
                      ],
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: VeilSpace.md),
                  Text(
                    bio,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ],
                if (contact.nickname != null &&
                    contact.nickname!.isNotEmpty) ...[
                  const SizedBox(height: VeilSpace.sm),
                  Text(
                    'Your nickname: ${contact.nickname}',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.textSubtle),
                  ),
                ],
                const SizedBox(height: VeilSpace.lg),
              ],
            ),
          ),
        );
      },
    );
  }
}
