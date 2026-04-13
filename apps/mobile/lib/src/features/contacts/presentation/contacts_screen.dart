import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class _Contact {
  const _Contact({
    required this.displayName,
    required this.handle,
    this.isOnline = false,
  });

  final String displayName;
  final String handle;
  final bool isOnline;
}

const _mockContacts = <_Contact>[
  _Contact(displayName: 'Adriana Voss', handle: 'avoss', isOnline: true),
  _Contact(displayName: 'Darian Cole', handle: 'dcole'),
  _Contact(displayName: 'Emiko Tanaka', handle: 'etanaka', isOnline: true),
  _Contact(displayName: 'Kieran Lau', handle: 'klau'),
  _Contact(displayName: 'Marcus Hale', handle: 'mhale', isOnline: true),
  _Contact(displayName: 'Nadia Petrov', handle: 'npetrov'),
  _Contact(displayName: 'Ren Ishikawa', handle: 'rishikawa'),
  _Contact(displayName: 'Soren Berg', handle: 'sberg', isOnline: true),
];

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
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

  List<_Contact> get _filteredContacts {
    if (_searchQuery.isEmpty) return _mockContacts;
    return _mockContacts
        .where((c) =>
            c.displayName.toLowerCase().contains(_searchQuery) ||
            c.handle.toLowerCase().contains(_searchQuery))
        .toList();
  }

  /// Groups contacts by the first letter of their display name.
  Map<String, List<_Contact>> _groupByLetter(List<_Contact> contacts) {
    final map = <String, List<_Contact>>{};
    for (final contact in contacts) {
      final letter = contact.displayName.characters.first.toUpperCase();
      map.putIfAbsent(letter, () => []).add(contact);
    }
    return map;
  }

  void _showContactActions(_Contact contact) {
    HapticFeedback.mediumImpact();
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
                        contact.displayName.characters.first.toUpperCase(),
                        style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              color: palette.primary,
                            ),
                      ),
                    ),
                    const SizedBox(width: VeilSpace.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.displayName,
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                        Text(
                          '@${contact.handle}',
                          style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                                color: palette.textSubtle,
                              ),
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
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        VeilToast.show(
                          context,
                          message: 'Starting conversation with ${contact.displayName}',
                          tone: VeilBannerTone.info,
                        );
                      },
                    ),
                    VeilButton(
                      label: 'View profile',
                      icon: Icons.person_outline_rounded,
                      tone: VeilButtonTone.secondary,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        VeilToast.show(
                          context,
                          message: 'Contact profiles not yet available',
                          tone: VeilBannerTone.info,
                        );
                      },
                    ),
                    VeilButton(
                      label: 'Remove contact',
                      icon: Icons.person_remove_outlined,
                      tone: VeilButtonTone.destructive,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        VeilToast.show(
                          context,
                          message: '${contact.displayName} removed from contacts',
                          tone: VeilBannerTone.danger,
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
    final contacts = _filteredContacts;
    final grouped = _groupByLetter(contacts);
    final letters = grouped.keys.toList()..sort();

    return VeilShell(
      title: 'Contacts',
      child: Column(
        children: [
          // Privacy banner
          VeilInlineBanner(
            message:
                'Contacts are stored on this device only. The relay does not maintain a contact list.',
            icon: Icons.devices_rounded,
          ),

          const SizedBox(height: VeilSpace.lg),

          // Search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts\u2026',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),

          const SizedBox(height: VeilSpace.sm),

          // Add contact button
          VeilButton(
            label: 'Add contact',
            icon: Icons.person_add_outlined,
            tone: VeilButtonTone.secondary,
            onPressed: () {
              HapticFeedback.selectionClick();
              VeilToast.show(
                context,
                message: 'Contact discovery requires relay lookup',
                tone: VeilBannerTone.warn,
              );
            },
          ),

          const SizedBox(height: VeilSpace.lg),

          // Contact list
          Expanded(
            child: contacts.isEmpty
                ? VeilEmptyState(
                    title: 'No contacts found',
                    body: _searchQuery.isNotEmpty
                        ? 'No contacts match your search.'
                        : 'Add contacts to start messaging securely.',
                    icon: Icons.people_outline_rounded,
                  )
                : ListView.builder(
                    itemCount: letters.length,
                    itemBuilder: (context, sectionIndex) {
                      final letter = letters[sectionIndex];
                      final sectionContacts = grouped[letter]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section header
                          Padding(
                            padding: const EdgeInsets.only(
                              top: VeilSpace.md,
                              bottom: VeilSpace.xs,
                            ),
                            child: Text(
                              letter,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: palette.textSubtle,
                              ),
                            ),
                          ),

                          // Contacts in this section
                          ...sectionContacts.map((contact) {
                            final glyph = contact.displayName.characters.first
                                .toUpperCase();

                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: VeilSpace.sm,
                              ),
                              child: VeilListTileCard(
                                title: contact.displayName,
                                subtitle: '@${contact.handle}',
                                leading: Stack(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: palette.primarySoft,
                                        border:
                                            Border.all(color: palette.stroke),
                                      ),
                                      child: Text(
                                        glyph,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: palette.primary,
                                        ),
                                      ),
                                    ),
                                    if (contact.isOnline)
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: palette.success,
                                            border: Border.all(
                                              color: palette.canvas,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.more_horiz_rounded,
                                  color: palette.textSubtle,
                                ),
                                onTap: () => _showContactActions(contact),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
