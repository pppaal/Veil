import 'package:flutter/material.dart';

import 'veil_group.dart';

export 'veil_group.dart';

// The rows of the previous pass, kept so the screens that use them compile
// until wave 1 moves them to VeilRow. Each is VeilRow with the old names.

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilRow.')
class VeilGroupRow extends StatelessWidget {
  const VeilGroupRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;

  /// Ignored: rows carry no decorative icon any more.
  final IconData? icon;
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return VeilRow(
      title: title,
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      leading: leading,
      value: value,
      trailing: trailing,
      onTap: onTap,
      destructive: destructive,
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilRow with switchValue and onSwitch.')
class VeilGroupSwitchRow extends StatelessWidget {
  const VeilGroupSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;

  /// Ignored: rows carry no decorative icon any more.
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return VeilRow(title: title, subtitle: subtitle, switchValue: value, onSwitch: onChanged);
  }
}
