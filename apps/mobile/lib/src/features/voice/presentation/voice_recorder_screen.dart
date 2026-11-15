import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_unavailable.dart';

/// Where a voice message would be recorded. This build has no audio plugin
/// and never opens the microphone, so the screen says that and leaves. It
/// shows no timer and no waveform: there is no recording for them to be
/// about.
class VoiceRecorderScreen extends StatelessWidget {
  const VoiceRecorderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilShell(
      title: l10n.voiceRecorderTitle,
      child: VeilUnavailable(
        icon: Icons.mic_off_outlined,
        title: l10n.voiceRecorderUnavailableTitle,
        body: l10n.voiceRecorderUnavailableBody,
        closeLabel: l10n.commonClose,
      ),
    );
  }
}
