import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_unavailable.dart';

/// Where one person's stories would play. A story reaches this device as a
/// sealed envelope and this build has nothing that opens one, so the
/// screen says that and leaves. It asks the relay for nothing and marks
/// nothing as viewed: the author is only ever told about a story that was
/// read.
class StoryViewerScreen extends StatelessWidget {
  const StoryViewerScreen({super.key, required this.authorUserId});

  /// Whose stories the route names.
  final String authorUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilShell(
      title: l10n.navStories,
      child: VeilUnavailable(
        icon: Icons.lock_outline_rounded,
        title: l10n.storyViewerUnavailableTitle,
        body: l10n.storyViewerUnavailableBody,
        closeLabel: l10n.commonClose,
      ),
    );
  }
}
