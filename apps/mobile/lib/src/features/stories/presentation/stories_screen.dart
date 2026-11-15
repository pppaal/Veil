import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/domain/conversation_preview.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/story_feed_providers.dart';

/// Who has a story up for this account, as the relay lists it: a row per
/// person with how many and how long ago. A story is a sealed envelope this
/// build cannot open, and it cannot seal one either, so a row opens
/// nothing, there is no button to post, and the line above the rows says
/// why. Nothing is marked as viewed from here.
class StoriesScreen extends ConsumerWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final storiesAsync = ref.watch(storyFeedProvider);

    return VeilShell(
      title: l10n.navStories,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storyFeedProvider);
          await ref.read(storyFeedProvider.future);
        },
        child: storiesAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: VeilSpace.xl),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (_, __) => ListView(
            children: [
              VeilInlineBanner(
                title: l10n.storiesUnavailableTitle,
                message: l10n.storiesUnavailableBody,
                tone: VeilBannerTone.danger,
              ),
            ],
          ),
          data: (stories) {
            final authors = storyAuthors(stories);
            // The notice is the first item, so it scrolls away with the
            // rows and the list keeps the whole height.
            return ListView.separated(
              itemCount: authors.isEmpty ? 2 : authors.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: VeilSpace.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return VeilInlineBanner(
                    dense: true,
                    icon: Icons.lock_outline_rounded,
                    message: l10n.storiesNotice,
                  );
                }
                if (authors.isEmpty) {
                  return VeilEmptyState(
                    title: l10n.storiesEmptyTitle,
                    body: l10n.storiesEmptyBody,
                    icon: Icons.amp_stories_outlined,
                  );
                }
                return _StoryAuthorRow(author: authors[index - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _StoryAuthorRow extends ConsumerWidget {
  const _StoryAuthorRow({required this.author});

  final StoryAuthor author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final name = _name(ref);

    return VeilListTileCard(
      title: name,
      subtitle: '${l10n.storiesRowCount(author.count)}  ·  ${storyAgeLabel(l10n, author.latest)}',
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primarySoft,
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          name.replaceFirst('@', '').characters.first.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: palette.primary),
        ),
      ),
      // Sealed, and it stays so here: the row has nothing to open.
      trailing: Icon(Icons.lock_outline_rounded, size: VeilIconSize.sm, color: palette.textSubtle),
    );
  }

  // The relay names an author by handle only. Someone this account chats
  // with goes by the name their chat shows.
  String _name(WidgetRef ref) {
    final conversations = ref.watch(messengerControllerProvider).conversations;
    for (final conversation in conversations) {
      if (conversation.type == ConversationType.direct &&
          conversation.recipientBundle.userId == author.userId &&
          conversation.peerDisplayName != null) {
        return conversation.peerDisplayName!;
      }
    }
    return '@${author.handle}';
  }
}

/// How long ago a story was posted. A story is gone after 24 hours, so
/// hours are the largest unit.
String storyAgeLabel(AppLocalizations l10n, DateTime postedAt, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(postedAt);
  if (age.inMinutes < 1) return l10n.storiesAgeJustNow;
  if (age.inHours < 1) return l10n.storiesAgeMinutes(age.inMinutes);
  return l10n.storiesAgeHours(age.inHours);
}
