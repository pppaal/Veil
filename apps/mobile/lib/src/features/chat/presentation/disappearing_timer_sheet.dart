import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

class _TtlOption {
  const _TtlOption({required this.label, required this.duration, this.caption});

  final String label;
  final Duration? duration;
  final String? caption;
}

List<_TtlOption> _ttlOptions(AppLocalizations l10n) => <_TtlOption>[
      _TtlOption(
        label: l10n.chatTtlOff,
        duration: null,
        caption: l10n.chatTtlOffCaption,
      ),
      _TtlOption(
        label: l10n.chatTtl10s,
        duration: const Duration(seconds: 10),
        caption: l10n.chatTtl10sCaption,
      ),
      _TtlOption(
        label: l10n.chatTtl1m,
        duration: const Duration(minutes: 1),
      ),
      _TtlOption(
        label: l10n.chatTtl5m,
        duration: const Duration(minutes: 5),
      ),
      _TtlOption(
        label: l10n.chatTtl1h,
        duration: const Duration(hours: 1),
      ),
      _TtlOption(
        label: l10n.chatTtl1d,
        duration: const Duration(days: 1),
        caption: l10n.chatTtl1dCaption,
      ),
    ];

/// The label of the disappearing-message timer [current] (null is off).
String disappearingTimerLabel(AppLocalizations l10n, Duration? current) {
  if (current == null) return l10n.chatTtlDisabledLabel;
  for (final option in _ttlOptions(l10n)) {
    if (option.duration == current) return option.label;
  }
  return l10n.chatTtlCustom;
}

/// Offers the disappearing-message timers, marking the one [current]
/// returns each time the sheet builds. Completes with null when the sheet
/// is dismissed without a choice, and otherwise with the chosen timer,
/// whose `ttl` is null for Off.
Future<({Duration? ttl})?> showDisappearingTimerSheet(
  BuildContext context, {
  required Duration? Function() current,
}) async {
  final l10n = AppLocalizations.of(context);
  final options = _ttlOptions(l10n);
  final sentinel = const Duration(microseconds: -1);
  final selected = await showModalBottomSheet<Duration?>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: Text(
                l10n.chatTtlSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(
                  current() == option.duration
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                ),
                title: Text(option.label),
                subtitle: option.caption == null ? null : Text(option.caption!),
                onTap: () =>
                    Navigator.of(sheetContext).pop<Duration?>(option.duration ?? sentinel),
              ),
            const SizedBox(height: VeilSpace.sm),
          ],
        ),
      );
    },
  );
  // Distinguish "dismissed without selection" (null) from "selected Off" (sentinel).
  if (selected == null) return null;
  return (ttl: selected == sentinel ? null : selected);
}
