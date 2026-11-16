import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Where a block, report or mute says how it went, taken once from the
/// screen it was started on: the app's root navigator and provider
/// container, which outlive that screen. The server may answer after the
/// user left the screen, and a Retry may be tapped on another one; either
/// still runs and says how it went. Nothing is said while the app is locked
/// or signed out: the lock shows nothing of the account.
class SafetyFeedback {
  SafetyFeedback.of(BuildContext context)
      : _context = Navigator.of(context, rootNavigator: true).context,
        _container = ProviderScope.containerOf(context, listen: false),
        l10n = AppLocalizations.of(context);

  final BuildContext _context;
  final ProviderContainer _container;
  final AppLocalizations l10n;

  /// What [provider] holds now, in the app rather than the screen.
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  /// Shows [message] in a toast; [retry] adds a Retry that runs it.
  void say(String message, {VeilTone tone = VeilTone.info, VoidCallback? retry}) {
    final session = _container.read(appSessionProvider);
    if (!_context.mounted || !session.isAuthenticated || session.locked) return;
    showVeilToast(
      _context,
      message,
      tone: tone,
      actionLabel: retry == null ? null : l10n.commonRetry,
      onAction: retry,
    );
  }
}
