import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What the assistant can be asked: each topic is one fixed question with
/// one prepared answer.
enum AiTopic { backup, newDevice, groups, calls }

/// The assistant as this build has it: no model, four questions, and a
/// prepared answer to each. The screen says so in a notice that stays put,
/// offers the questions as buttons (there is no field to type into, because
/// nothing would read what was typed), and shows an answer the moment its
/// question is tapped, with no pretended thinking. Nothing leaves the
/// device.
///
/// An answer may only state what this build does.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _scrollController = ScrollController();
  final List<AiTopic> _asked = [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ask(AiTopic topic) {
    VeilHaptics.light();
    setState(() => _asked.add(topic));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: VeilMotion.normal,
        curve: VeilMotion.emphasize,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final open = [for (final topic in AiTopic.values) if (!_asked.contains(topic)) topic];

    return VeilShell(
      title: l10n.aiTitle,
      padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.sm, VeilSpace.lg, VeilSpace.md),
      actions: [
        IconButton(
          tooltip: l10n.aiClearTooltip,
          onPressed: _asked.isEmpty ? null : () => setState(_asked.clear),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Outside the scrolling list on purpose: the disclosure must stay
          // visible however long the conversation gets.
          VeilInlineBanner(
            dense: true,
            title: l10n.aiDemoBannerTitle,
            message: l10n.aiDemoBannerBody,
            icon: Icons.smart_toy_outlined,
          ),
          const SizedBox(height: VeilSpace.sm),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: [
                _Bubble(speaker: l10n.aiTitle, text: l10n.aiIntro),
                for (final topic in _asked) ...[
                  const SizedBox(height: VeilSpace.sm),
                  _Bubble(text: _question(l10n, topic), mine: true),
                  const SizedBox(height: VeilSpace.sm),
                  _Bubble(speaker: l10n.aiTitle, text: _answer(l10n, topic)),
                ],
              ],
            ),
          ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: VeilSpace.sm),
            Wrap(
              spacing: VeilSpace.xs,
              children: [
                for (final topic in open)
                  ActionChip(
                    label: Text(_question(l10n, topic)),
                    onPressed: () => _ask(topic),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _question(AppLocalizations l10n, AiTopic topic) => switch (topic) {
        AiTopic.backup => l10n.aiQuestionBackup,
        AiTopic.newDevice => l10n.aiQuestionNewDevice,
        AiTopic.groups => l10n.aiQuestionGroups,
        AiTopic.calls => l10n.aiQuestionCalls,
      };

  String _answer(AppLocalizations l10n, AiTopic topic) => switch (topic) {
        AiTopic.backup => l10n.aiAnswerBackup,
        AiTopic.newDevice => l10n.aiAnswerNewDevice,
        AiTopic.groups => l10n.aiAnswerGroups,
        AiTopic.calls => l10n.aiAnswerCalls,
      };
}

/// One turn, drawn like a chat's bubbles: the question on the user's side,
/// the prepared answer on the other with who it is from.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, this.speaker, this.mine = false});

  final String text;
  final String? speaker;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final speaker = this.speaker;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: VeilMessageBubbleCard(
        isMine: mine,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speaker != null) ...[
              Text(speaker, style: theme.textTheme.labelMedium?.copyWith(color: palette.textMuted)),
              const SizedBox(height: VeilSpace.xxs),
            ],
            VeilCopy(
              text,
              // White on the violet of the user's side, in either theme.
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.38, color: mine ? Colors.white : null),
            ),
          ],
        ),
      ),
    );
  }
}
