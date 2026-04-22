import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class StickerPickerScreen extends StatefulWidget {
  const StickerPickerScreen({super.key, this.onEmojiSelected});

  final ValueChanged<String>? onEmojiSelected;

  @override
  State<StickerPickerScreen> createState() => _StickerPickerScreenState();
}

class _StickerPickerScreenState extends State<StickerPickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _tabs = ['Emoji', 'Stickers', 'GIFs'];

  static const _categories = [
    ('Smileys', Icons.emoji_emotions_outlined),
    ('People', Icons.people_outline_rounded),
    ('Animals', Icons.pets_outlined),
    ('Food', Icons.restaurant_outlined),
    ('Travel', Icons.flight_outlined),
    ('Objects', Icons.lightbulb_outline_rounded),
    ('Symbols', Icons.favorite_border_rounded),
    ('Flags', Icons.flag_outlined),
  ];

  static const _recentEmoji = [
    '\u{1F44D}', '\u{2764}\u{FE0F}', '\u{1F602}', '\u{1F525}',
    '\u{1F60E}', '\u{1F64F}',
  ];

  static const _allEmoji = [
    // Smileys
    '\u{1F600}', '\u{1F603}', '\u{1F604}', '\u{1F601}', '\u{1F606}',
    '\u{1F605}', '\u{1F602}', '\u{1F923}', '\u{1F60A}', '\u{1F607}',
    '\u{1F642}', '\u{1F643}', '\u{1F609}', '\u{1F60C}', '\u{1F60D}',
    '\u{1F970}', '\u{1F618}', '\u{1F617}', '\u{1F619}', '\u{1F61A}',
    // People & gestures
    '\u{1F60B}', '\u{1F61B}', '\u{1F61C}', '\u{1F92A}', '\u{1F61D}',
    '\u{1F911}', '\u{1F917}', '\u{1F92D}', '\u{1F92B}', '\u{1F914}',
    '\u{1F910}', '\u{1F928}', '\u{1F610}', '\u{1F611}', '\u{1F636}',
    '\u{1F60F}', '\u{1F612}', '\u{1F644}', '\u{1F62C}', '\u{1F925}',
    // Emotional
    '\u{1F60E}', '\u{1F913}', '\u{1F9D0}', '\u{1F615}', '\u{1F61F}',
    '\u{1F641}', '\u{2639}\u{FE0F}', '\u{1F62E}', '\u{1F62F}', '\u{1F632}',
    '\u{1F633}', '\u{1F97A}', '\u{1F626}', '\u{1F627}', '\u{1F628}',
    '\u{1F630}', '\u{1F625}', '\u{1F622}', '\u{1F62D}', '\u{1F631}',
    // Gestures & symbols
    '\u{1F44D}', '\u{1F44E}', '\u{1F44A}', '\u{270A}', '\u{1F91B}',
    '\u{1F91C}', '\u{1F44F}', '\u{1F64C}', '\u{1F450}', '\u{1F64F}',
    '\u{2764}\u{FE0F}', '\u{1F9E1}', '\u{1F49B}', '\u{1F49A}', '\u{1F499}',
    '\u{1F49C}', '\u{1F525}', '\u{2B50}', '\u{1F31F}', '\u{1F4AB}',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _selectEmoji(String emoji) {
    VeilHaptics.selection();
    if (widget.onEmojiSelected != null) {
      widget.onEmojiSelected!(emoji);
    } else {
      VeilToast.show(
        context,
        message: 'Selected $emoji',
        tone: VeilBannerTone.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return VeilShell(
      title: 'Stickers',
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VeilSpace.lg, VeilSpace.sm, VeilSpace.lg, VeilSpace.sm,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search emoji and stickers',
                prefixIcon: Icon(Icons.search_rounded),
                prefixIconConstraints: BoxConstraints(
                  minHeight: 40,
                  minWidth: 40,
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: palette.primary,
            labelColor: palette.text,
            unselectedLabelColor: palette.textSubtle,
            dividerColor: palette.stroke,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEmojiTab(palette, theme),
                _buildStickersTab(),
                _buildGifsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiTab(VeilPalette palette, ThemeData theme) {
    final filtered = _searchQuery.isEmpty
        ? _allEmoji
        : _allEmoji; // No text-based filter for emoji glyphs

    return CustomScrollView(
      slivers: [
        if (_searchQuery.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.xs,
              ),
              child: VeilSectionLabel('RECENTLY USED'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: VeilSpace.xs,
                crossAxisSpacing: VeilSpace.xs,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _EmojiCell(
                  emoji: _recentEmoji[index],
                  onTap: () => _selectEmoji(_recentEmoji[index]),
                  palette: palette,
                ),
                childCount: _recentEmoji.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                VeilSpace.lg, VeilSpace.lg, VeilSpace.lg, VeilSpace.xs,
              ),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: VeilSpace.xs),
                  itemBuilder: (context, index) {
                    final (label, icon) = _categories[index];
                    return ActionChip(
                      avatar: Icon(icon, size: VeilIconSize.sm),
                      label: Text(label),
                      onPressed: () {},
                    );
                  },
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.xs,
              ),
              child: VeilSectionLabel('ALL EMOJI'),
            ),
          ),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VeilSpace.lg, VeilSpace.xs, VeilSpace.lg, VeilSpace.xl,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: VeilSpace.xs,
              crossAxisSpacing: VeilSpace.xs,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _EmojiCell(
                emoji: filtered[index],
                onTap: () => _selectEmoji(filtered[index]),
                palette: palette,
              ),
              childCount: filtered.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickersTab() {
    return const VeilEmptyState(
      title: 'Custom sticker packs',
      body: 'Custom sticker packs coming soon. '
          'Stickers will be encrypted the same as all other media.',
      icon: Icons.sticky_note_2_outlined,
    );
  }

  Widget _buildGifsTab() {
    return const VeilEmptyState(
      title: 'GIF search',
      body: 'GIF search requires external service integration. '
          'Privacy-preserving proxy under evaluation.',
      icon: Icons.gif_box_outlined,
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({
    required this.emoji,
    required this.onTap,
    required this.palette,
  });

  final String emoji;
  final VoidCallback onTap;
  final VeilPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.sm),
        onTap: onTap,
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}
