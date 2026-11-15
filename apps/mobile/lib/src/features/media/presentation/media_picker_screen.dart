import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_unavailable.dart';

/// Where photos and videos would be chosen for a chat. This build has no
/// gallery or camera plugin, so there is nothing to list and nothing to
/// send: the screen says that and leaves. It draws no grid before there are
/// pictures to put in one.
class MediaPickerScreen extends StatelessWidget {
  const MediaPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilShell(
      title: l10n.mediaPickerTitle,
      child: VeilUnavailable(
        icon: Icons.photo_library_outlined,
        title: l10n.mediaPickerUnavailableTitle,
        body: l10n.mediaPickerUnavailableBody,
        closeLabel: l10n.commonClose,
      ),
    );
  }
}
