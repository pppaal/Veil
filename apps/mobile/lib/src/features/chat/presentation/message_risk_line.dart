import 'package:flutter/material.dart';

import '../../../core/safety/message_risk.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What the line under a flagged message says: what it asks for or claims,
/// and what to do. An app file sent as a file is named as one ([file]).
String riskLineText(AppLocalizations l10n, RiskReason reason, {bool file = false}) => switch (reason) {
      RiskReason.familyClaim => l10n.riskLineFamilyClaim,
      RiskReason.newPhoneClaim => l10n.riskLineNewPhoneClaim,
      RiskReason.asksForMoney => l10n.riskLineMoney,
      RiskReason.asksForGiftCard => l10n.riskLineGiftCard,
      RiskReason.asksForCode => l10n.riskLineCode,
      RiskReason.asksForId => l10n.riskLineId,
      RiskReason.asksToInstallApp => l10n.riskLineRemoteApp,
      RiskReason.appFile => file ? l10n.riskLineAppFileAttached : l10n.riskLineAppFile,
      RiskReason.lookalikeLink => l10n.riskLineLookalikeLink,
      RiskReason.hiddenLink => l10n.riskLineHiddenLink,
      RiskReason.fakeDelivery => l10n.riskLineDelivery,
      RiskReason.fakeBank => l10n.riskLineBank,
      RiskReason.fakeAuthority => l10n.riskLineAuthority,
      RiskReason.fakeGovernment => l10n.riskLineGovernment,
      RiskReason.investment => l10n.riskLineInvestment,
    };

/// The colour of a line of [level]: muted for mild, the warning colour for
/// warn, the danger colour for strong.
Color riskLineColor(VeilPalette palette, RiskLevel level) => switch (level) {
      RiskLevel.strong => palette.danger,
      RiskLevel.warn => palette.warning,
      RiskLevel.mild || RiskLevel.none => palette.textMuted,
    };

/// One line under a message the checks on this phone flagged, in the slot
/// of the legacy sender line and after it: a 14 dp glyph (info for mild, a
/// warning triangle for warn, an error circle for strong) and the reason in
/// small type, in the tone of its level, at most three lines. A screen
/// reader hears the words. It cannot be dismissed, and none is drawn for
/// [RiskLevel.none].
class MessageRiskLine extends StatelessWidget {
  const MessageRiskLine({super.key, required this.risk, this.file = false});

  final MessageRisk risk;

  /// The message is a file: an app file is "This is an app file".
  final bool file;

  @override
  Widget build(BuildContext context) {
    final reason = risk.reason;
    if (risk.level == RiskLevel.none || reason == null) return const SizedBox.shrink();
    final text = riskLineText(AppLocalizations.of(context), reason, file: file);
    final color = riskLineColor(context.veilPalette, risk.level);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    final icon = switch (risk.level) {
      RiskLevel.strong => Icons.error_outline,
      RiskLevel.warn => Icons.warning_amber_outlined,
      _ => Icons.info_outline,
    };
    // The glyph sits on the first line of the text, whatever its size.
    final lineHeight = (style?.fontSize ?? 12) * (style?.height ?? 1.3);
    // A node of its own, so it is heard as its words after the message.
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: lineHeight,
            child: Icon(icon, size: VeilIconSize.xs, color: color),
          ),
          const SizedBox(width: VeilSpace.xxs),
          Flexible(
            child: Text(text, style: style, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
