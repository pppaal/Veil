import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/link_opener.dart';
import '../../../core/safety/links.dart';
import '../../../core/safety/message_risk.dart';
import '../../../core/safety/rule_risk_checker.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What a tap on [link] in a message does. A link that downloads an app,
/// hides where it goes (a short link, an IP address, a login before the
/// host, an odd port, an escape or a non-Latin letter in the host,
/// punycode) or only looks like a known site asks
/// through the strong sheet, whoever sent it. Any other link asks through
/// the plain sheet unless [openAtOnce] (the user's own message, or a
/// verified sender in an accepted chat); a company's own short link
/// (naver.me, kko.to, me2.do) always asks through the plain one. Both
/// sheets show in bold the domain a browser would open for the forms this
/// code reads: %-escapes decoded, ideographic and full-width full stops
/// read as dots, full-width letters and digits read as plain ones, and
/// non-Latin labels in their xn-- form. It does not apply every UTS46
/// mapping a browser does. A host a browser would refuse (an escape that
/// does not decode, or one that decodes to a character no host may hold)
/// is shown as the address escapes it. Under the domain is the address
/// that opens; nothing about the link is fetched, previewed or expanded,
/// before or after.
Future<void> openMessageLink(
  BuildContext context,
  FoundLink link, {
  required LinkOpener opener,
  required bool openAtOnce,
}) async {
  final risk = linkRiskOf(link);
  final strong = risk == LinkRisk.appFile || risk == LinkRisk.lookalike || risk == LinkRisk.hidden;
  if (!strong && openAtOnce && risk == LinkRisk.none) return _open(context, opener, link.uri);
  VeilHaptics.selection();
  final choice = await showModalBottomSheet<_LinkChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LinkSheet(link: link, risk: strong ? risk : null),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _LinkChoice.open:
      await _open(context, opener, link.uri);
    case _LinkChoice.copy:
      await Clipboard.setData(ClipboardData(text: link.uri.toString()));
      if (context.mounted) showVeilToast(context, AppLocalizations.of(context).linkCopied);
    case null:
      break;
  }
}

Future<void> _open(BuildContext context, LinkOpener opener, Uri uri) async {
  final failed = AppLocalizations.of(context).linkOpenFailed;
  if (await opener.open(uri)) return;
  if (context.mounted) showVeilToast(context, failed);
}

/// Whether a file called [name] is an Android app (.apk, .xapk, .apks),
/// which opens or saves only through [confirmAppFile].
bool isAppFileName(String name) =>
    const RuleRiskChecker().assessFileName(name, RiskRelationship.unknown).reason == RiskReason.appFile;

/// Asks before an app file called [name] is opened or, with [saving],
/// saved: whoever sent it, the strong sheet says what an app from a chat
/// can do, with "Don't open" (or "Don't save") filled and the way on below
/// it in red. True only when the user chose to go on.
Future<bool> confirmAppFile(BuildContext context, {required String name, bool saving = false}) async {
  VeilHaptics.selection();
  final choice = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AppFileSheet(name: name, saving: saving),
  );
  return choice == true;
}

enum _LinkChoice { open, copy }

/// The middle of [text] left out past [max] characters, so its start (the
/// host) and its end both show.
String _middleCut(String text, {int max = 120}) {
  if (text.length <= max) return text;
  final half = (max - 1) ~/ 2;
  return '${text.substring(0, half)}…${text.substring(text.length - half)}';
}

/// "Open this link?" with the domain and the address, then Open and Copy
/// link; or, for a [risk]y link, what is wrong with it, a filled "Don't
/// open", then Open anyway in red and Copy link. Closing it opens nothing.
class _LinkSheet extends StatelessWidget {
  const _LinkSheet({required this.link, required this.risk});

  final FoundLink link;

  /// Null for the plain sheet.
  final LinkRisk? risk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final risk = this.risk;
    final (title, body) = switch (risk) {
      LinkRisk.appFile => (l10n.linkRiskAppTitle, l10n.linkRiskAppBody),
      LinkRisk.hidden => (l10n.linkRiskHiddenTitle, l10n.linkRiskHiddenBody),
      LinkRisk.lookalike => (l10n.linkRiskLookalikeTitle, l10n.linkRiskLookalikeBody),
      _ => (l10n.linkConfirmTitle, null),
    };
    void choose(_LinkChoice choice) => Navigator.of(context).pop<_LinkChoice>(choice);
    return _SheetBody(
      words: [
        Text(title, style: theme.textTheme.titleLarge),
        if (body != null) ...[
          const SizedBox(height: VeilSpace.xxs),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
        ],
        const SizedBox(height: VeilSpace.sm),
        Text(link.registrableDomain, key: const ValueKey('link-sheet-domain'), style: theme.textTheme.titleMedium),
        Text(
          _middleCut(link.uri.toString()),
          key: const ValueKey('link-sheet-address'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
        ),
        if (risk != null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilButton(label: l10n.linkRiskKeepClosed, onPressed: () => Navigator.of(context).pop()),
        ],
        const SizedBox(height: VeilSpace.sm),
      ],
      rows: [
        VeilRow(
          key: const ValueKey('link-sheet-open'),
          title: risk == null ? l10n.linkConfirmOpen : l10n.linkRiskOpenAnyway,
          destructive: risk != null,
          trailing: const SizedBox.shrink(),
          onTap: () => choose(_LinkChoice.open),
        ),
        VeilRow(
          key: const ValueKey('link-sheet-copy'),
          title: l10n.linkConfirmCopy,
          trailing: const SizedBox.shrink(),
          onTap: () => choose(_LinkChoice.copy),
        ),
      ],
    );
  }
}

/// "This file is an app": what an app from a chat can do, the file's name,
/// a filled "Don't open" ("Don't save"), and Open anyway (Save anyway) in
/// red. Closing it does nothing.
class _AppFileSheet extends StatelessWidget {
  const _AppFileSheet({required this.name, required this.saving});

  final String name;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return _SheetBody(
      words: [
        Text(l10n.fileRiskAppTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: VeilSpace.xxs),
        Text(l10n.linkRiskAppBody, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
        const SizedBox(height: VeilSpace.sm),
        Text(_middleCut(name, max: 80), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
        const SizedBox(height: VeilSpace.md),
        VeilButton(
          label: saving ? l10n.fileRiskDontSave : l10n.linkRiskKeepClosed,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: VeilSpace.sm),
      ],
      rows: [
        VeilRow(
          key: const ValueKey('app-file-go-on'),
          title: saving ? l10n.fileRiskSaveAnyway : l10n.linkRiskOpenAnyway,
          destructive: true,
          trailing: const SizedBox.shrink(),
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// A sheet's words in the page margins, then its rows edge to edge.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.words, required this.rows});

  final List<Widget> words;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: VeilSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: words,
              ),
            ),
            VeilGroup(children: rows),
          ],
        ),
      ),
    );
  }
}
