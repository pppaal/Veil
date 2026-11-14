import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The top of a chat: who it is with and whether they are online, the
/// disappearing-message timer, and the local message search. Standalone,
/// a hero panel sits above it.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.embedded,
    required this.title,
    required this.searchController,
    required this.searching,
    required this.ttlLabel,
    required this.ttlActive,
    required this.onTapTtl,
    this.peerOnline = false,
  });

  final bool embedded;
  final String title;
  final TextEditingController searchController;
  final bool searching;
  final String ttlLabel;
  final bool ttlActive;
  final VoidCallback onTapTtl;
  final bool peerOnline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final header = Column(
      children: [
        VeilSurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: VeilSpace.lg,
            vertical: VeilSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (peerOnline) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: VeilSpace.xs),
                        ],
                        Expanded(
                          child: Text(
                            embedded ? title : l10n.chatTitleFallback,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: VeilSpace.xxs),
                    Text(
                      peerOnline
                          ? l10n.chatSubtitleOnline
                          : embedded
                              ? l10n.chatSubtitleEmbedded
                              : l10n.chatSubtitleStandalone,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: peerOnline ? palette.success : null,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VeilSpace.sm),
              VeilButton(
                expanded: false,
                tone: ttlActive
                    ? VeilButtonTone.primary
                    : VeilButtonTone.secondary,
                icon: Icons.timer_outlined,
                onPressed: onTapTtl,
                label: ttlLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          padding: const EdgeInsets.all(VeilSpace.md),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.chatSearchClearTooltip,
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                  hintText: l10n.chatSearchHint,
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VeilStatusPill(
                    label: ttlLabel,
                    tone: ttlActive
                        ? VeilBannerTone.warn
                        : VeilBannerTone.info,
                  ),
                  VeilStatusPill(label: l10n.chatPillAttachmentsEncrypted),
                  VeilStatusPill(label: l10n.chatPillLocalSearchOnly),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (embedded) {
      return header;
    }

    return Column(
      children: [
        VeilHeroPanel(
          eyebrow: l10n.chatHeroEyebrow,
          title: title,
          body: l10n.chatHeroBody,
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: ttlLabel,
                tone: ttlActive ? VeilBannerTone.warn : VeilBannerTone.info,
              ),
              VeilStatusPill(label: l10n.chatPillAttachmentsEncrypted),
              VeilStatusPill(label: l10n.chatPillLocalSearchOnly),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        header,
      ],
    );
  }
}
