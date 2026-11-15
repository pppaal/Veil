import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_initial_badge.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_unavailable.dart';

/// Where a call with one person would run. This build has no call engine
/// (no WebRTC, no audio or video capture), so the screen has one state: it
/// names the person, says that no call can be made here, and leaves. It
/// starts nothing at the relay, so the other side is never rung.
///
/// A call engine brings its own states (ringing, connected, ended) and the
/// controls that act on them; none is drawn here before one exists.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.contactName});

  /// Who the call would be with; empty when the screen was opened without
  /// a name.
  final String contactName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = contactName.trim();
    return VeilShell(
      title: l10n.callScreenTitle,
      child: VeilUnavailable(
        header: name.isEmpty ? null : _CallPeer(name: name),
        icon: Icons.phone_disabled_rounded,
        title: l10n.callScreenUnavailableTitle,
        body: l10n.callScreenUnavailableBody,
        closeLabel: l10n.commonClose,
      ),
    );
  }
}

class _CallPeer extends StatelessWidget {
  const _CallPeer({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VeilInitialBadge(name: name, size: 88),
        const SizedBox(height: VeilSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
          child: Text(
            name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
