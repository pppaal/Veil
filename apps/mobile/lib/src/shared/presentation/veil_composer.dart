import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// The strip at the bottom of a chat: the draft in a grey field (fill
/// `surfaceAlt`, rounded by 18, 36dp tall in a 44dp row, up to five lines)
/// with the hint in muted type, [leading] before it (attach) and [trailing]
/// after it (the chat's send button, which keeps a 32dp slot while the
/// draft is empty). The strip sits on the page with a hairline above it.
///
/// A composer that is not [enabled] shows its reason ([helper]) as the hint.
class VeilComposer extends StatelessWidget {
  const VeilComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
    required this.trailing,
    required this.label,
    this.leading,
    this.helper,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;
  final Widget trailing;

  /// A control before the draft (attach). Nothing by default.
  final Widget? leading;

  /// Why the composer is disabled, shown as the hint while it is.
  final String? helper;

  /// The hint in the empty draft.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final hint = enabled ? label : (helper ?? label);

    final field = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(VeilRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 1,
          maxLines: 5,
          enabled: enabled,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSubmit(),
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: palette.textMuted),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            // 7 above and below a 16/1.4 line make the 36 of the field.
            contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: 7),
            isDense: true,
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(top: BorderSide(color: palette.stroke, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: VeilSpace.xxs)],
              // 4 above and below the 36 field centre it on the 44 of the
              // buttons beside it; more lines grow it upward.
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: field)),
              const SizedBox(width: VeilSpace.xs),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
