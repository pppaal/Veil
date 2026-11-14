import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/safety_numbers.dart';
import 'safety_number_cards.dart';

/// Asks the user to affirm, next to the new number, that they compared it
/// out of band; pops true only with that affirmation.
class SafetyReverifyDialog extends StatefulWidget {
  const SafetyReverifyDialog({super.key, required this.peer, required this.number});

  final String peer;
  final String number;

  @override
  State<SafetyReverifyDialog> createState() => _SafetyReverifyDialogState();
}

class _SafetyReverifyDialogState extends State<SafetyReverifyDialog> {
  bool _compared = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.safetyNumbersReverifyDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.safetyNumbersReverifyDialogBody(widget.peer)),
            const SizedBox(height: VeilSpace.md),
            SafetyNumberCard(groups: formatSafetyNumber(widget.number)),
            CheckboxListTile(
              value: _compared,
              onChanged: (value) => setState(() => _compared = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.safetyNumbersReverifyAffirm(widget.peer)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.safetyNumbersCancel),
        ),
        TextButton(
          onPressed: _compared ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.safetyNumbersReverifyAccept),
        ),
      ],
    );
  }
}

/// Takes the code scanned from the peer's screen; pops its text.
class SafetyScannedCodeDialog extends StatefulWidget {
  const SafetyScannedCodeDialog({super.key});

  @override
  State<SafetyScannedCodeDialog> createState() => _SafetyScannedCodeDialogState();
}

class _SafetyScannedCodeDialogState extends State<SafetyScannedCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.safetyNumbersScanAction),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.safetyNumbersScanFieldLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.safetyNumbersCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.safetyNumbersScanVerify),
        ),
      ],
    );
  }
}
