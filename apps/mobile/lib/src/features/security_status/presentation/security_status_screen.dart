import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SecurityStatusScreen extends ConsumerWidget {
  const SecurityStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final messenger = ref.watch(messengerControllerProvider);
    final localSecurity = ref.watch(localSecuritySnapshotProvider);
    final cacheConfigured = VeilConfig.enableLocalCache;
    final cacheReady = ref.watch(conversationCacheProvider).maybeWhen(
          data: (cache) => cache != null,
          orElse: () => false,
        );

    final identitySignals = <_SecuritySignal>[
      _SecuritySignal(
        label: 'Bound device',
        value:
            session.deviceId == null ? 'Unbound' : _shortId(session.deviceId!),
        detail: session.deviceId == null
            ? 'No active device session is present.'
            : 'This device currently holds the active VEIL session.',
        tone: session.deviceId == null ? _SignalTone.warn : _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Local secret refs',
        value: localSecurity.maybeWhen(
          data: (state) => state.hasDeviceSecretRefs ? 'Present' : 'Missing',
          orElse: () => 'Checking',
        ),
        detail:
            'Private device material stays on the device. The server never receives it.',
        tone: localSecurity.maybeWhen(
          data: (state) =>
              state.hasDeviceSecretRefs ? _SignalTone.good : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: 'App lock PIN',
        value: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? 'Configured' : 'Unset',
          orElse: () => 'Checking',
        ),
        detail: 'Local barrier only. VEIL cannot unlock the app for you.',
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? _SignalTone.good : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: 'Biometrics',
        value: localSecurity.maybeWhen(
          data: (state) =>
              state.biometricsAvailable ? 'Available' : 'Unavailable',
          orElse: () => 'Checking',
        ),
        detail:
            'Device-level biometric unlock only. No remote fallback exists.',
        tone: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable
              ? _SignalTone.good
              : _SignalTone.neutral,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      const _SecuritySignal(
        label: 'Privacy shield',
        value: 'Enabled',
        detail:
            'When VEIL leaves the foreground, the app obscures previews and re-arms the local barrier.',
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Recent-app preview',
        value: localSecurity.maybeWhen(
          data: (state) =>
              state.appPreviewProtectionEnabled ? 'Protected' : 'Partial',
          orElse: () => 'Checking',
        ),
        detail:
            'Native and Flutter privacy shields are used to hide app-switcher content while VEIL is backgrounded.',
        tone: localSecurity.maybeWhen(
          data: (state) => state.appPreviewProtectionEnabled
              ? _SignalTone.good
              : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: 'Screen capture',
        value: localSecurity.maybeWhen(
          data: (state) => !state.screenCaptureProtectionSupported
              ? 'Platform-limited'
              : state.screenCaptureProtectionEnabled
                  ? 'Blocked'
                  : 'Not blocked',
          orElse: () => 'Checking',
        ),
        detail: localSecurity.maybeWhen(
          data: (state) => state.screenCaptureProtectionSupported
              ? 'Android blocks screenshots with secure-window flags when enabled.'
              : 'This platform has no public API for full screenshot blocking, so VEIL relies on preview shielding and rapid relocking instead.',
          orElse: () => 'Checking native screen-capture policy.',
        ),
        tone: localSecurity.maybeWhen(
          data: (state) => !state.screenCaptureProtectionSupported
              ? _SignalTone.neutral
              : state.screenCaptureProtectionEnabled
                  ? _SignalTone.good
                  : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      const _SecuritySignal(
        label: 'Clipboard hygiene',
        value: 'Restricted',
        detail:
            'Sensitive attachment tickets are summarized locally instead of exposing raw signed URLs for copy/share.',
        tone: _SignalTone.good,
      ),
    ];

    final runtimeSignals = <_SecuritySignal>[
      _SecuritySignal(
        label: 'Transport policy',
        value: VeilConfig.runtimeConfigurationError == null
            ? 'Compliant'
            : 'Blocked',
        detail: VeilConfig.runtimeConfigurationError == null
            ? 'Configured endpoints satisfy the current private-beta transport policy.'
            : VeilConfig.runtimeConfigurationError!,
        tone: VeilConfig.runtimeConfigurationError == null
            ? _SignalTone.good
            : _SignalTone.warn,
      ),
      _SecuritySignal(
        label: 'API mode',
        value: VeilConfig.hasApi ? 'Attached' : 'Unavailable',
        detail: VeilConfig.hasApi
            ? 'REST API is configured for this build.'
            : 'No API endpoint is configured. Messaging is unavailable.',
        tone: VeilConfig.hasApi ? _SignalTone.good : _SignalTone.warn,
      ),
      _SecuritySignal(
        label: 'Relay link',
        value: messenger.realtimeConnected ? 'Connected' : 'Idle',
        detail: messenger.realtimeConnected
            ? 'Realtime relay is connected with opaque event payloads.'
            : 'Realtime relay is disconnected or still syncing.',
        tone: messenger.realtimeConnected
            ? _SignalTone.good
            : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: 'Local cache',
        value: !cacheConfigured
            ? 'Disabled'
            : cacheReady
                ? 'Ready'
                : 'Starting',
        detail: !cacheConfigured
            ? 'Local message cache is disabled in this build.'
            : 'Conversations and envelopes are cached locally behind the current private-beta encrypted-at-rest layer, scrubbed from app-switcher previews, and wiped on destructive local lifecycle events.',
        tone: !cacheConfigured
            ? _SignalTone.warn
            : cacheReady
                ? _SignalTone.good
                : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: 'Device integrity',
        value: localSecurity.maybeWhen(
          data: (state) => state.integrityCompromised ? 'Compromised' : 'Clean',
          orElse: () => 'Checking',
        ),
        detail: localSecurity.maybeWhen(
          data: (state) => state.integrityCompromised
              ? state.integrityReasons.isEmpty
                  ? 'This device matched rooted or jailbroken heuristics. VEIL blocks local unlock in this state.'
                  : 'This device matched rooted or jailbroken heuristics. ${state.integrityReasons.join(' | ')}'
              : 'Native rooted and jailbroken heuristics did not trigger on this device.',
          orElse: () => 'Checking native integrity heuristics.',
        ),
        tone: localSecurity.maybeWhen(
          data: (state) =>
              state.integrityCompromised ? _SignalTone.warn : _SignalTone.good,
          orElse: () => _SignalTone.neutral,
        ),
      ),
    ];

    final productSignals = <_SecuritySignal>[
      _SecuritySignal(
        label: 'Cloud backup',
        value: 'Disabled',
        detail: 'VEIL does not keep a recovery copy of your message history.',
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Account recovery',
        value: 'Unavailable',
        detail: 'No recovery email, reset flow, or admin restore path exists.',
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Device transfer',
        value: 'Old device required',
        detail: 'Transfer succeeds only while the old device can approve it.',
        tone: _SignalTone.good,
      ),
      const _SecuritySignal(
        label: 'Local wipe',
        value: 'Available',
        detail:
            'This device can erase local session state, local secrets, encrypted cache, and the local barrier without creating a recovery path.',
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Crypto adapter',
        value: 'Mock active',
        detail:
            'Dev-only opaque payloads are active. Audited production crypto is still required.',
        tone: _SignalTone.warn,
      ),
      _SecuritySignal(
        label: 'Push plaintext',
        value: 'Forbidden',
        detail: 'Push payloads must never contain plaintext message content.',
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: 'Push provider',
        value: VeilConfig.hasApi ? 'Seam only' : 'Unavailable',
        detail: VeilConfig.hasApi
            ? 'The metadata-only wake-up path is defined, but a real APNs/FCM provider is not wired in this build.'
            : 'No API endpoint is configured, so push delivery is unavailable in this build.',
        tone: VeilConfig.hasApi ? _SignalTone.warn : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: 'Push payloads',
        value: VeilConfig.hasApi ? 'Metadata only' : 'Unavailable',
        detail: VeilConfig.hasApi
            ? 'If push is enabled later, wake-up hints must stay metadata-only. Message bodies remain out of push.'
            : 'No API endpoint is configured, so push payload generation is unavailable in this build.',
        tone: VeilConfig.hasApi ? _SignalTone.good : _SignalTone.neutral,
      ),
    ];

    return VeilShell(
      title: 'Security Status',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'SECURITY STATUS',
            title: 'No backup. No recovery. No leaks.',
            body:
                'This panel reflects the current device and runtime state. If a guardrail is missing here, it is missing on the device.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'Private beta'),
                VeilStatusPill(
                    label: 'Mock crypto active', tone: VeilBannerTone.warn),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(
                label: 'Runtime',
                value: VeilConfig.runtimeConfigurationError == null ? 'Ready' : 'Blocked',
              ),
              VeilMetricItem(
                label: 'Relay',
                value: messenger.realtimeConnected ? 'Linked' : 'Idle',
              ),
              VeilMetricItem(
                label: 'Cache',
                value: !cacheConfigured
                    ? 'Off'
                    : cacheReady
                        ? 'Ready'
                        : 'Starting',
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          const _SecuritySection(title: 'Identity'),
          ...identitySignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: VeilSpace.md),
          const _SecuritySection(title: 'Runtime'),
          ...runtimeSignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: VeilSpace.md),
          const _SecuritySection(title: 'Product Rules'),
          ...productSignals.map((signal) => _SecurityRow(signal: signal)),
        ],
      ),
    );
  }

  static String _shortId(String value) {
    if (value.length <= 12) {
      return value;
    }

    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: VeilSpace.xs),
      child: VeilSectionLabel(title.toUpperCase()),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({required this.signal});

  final _SecuritySignal signal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VeilSpace.sm),
      child: VeilValueRow(
        label: signal.label,
        value: signal.value,
        valueTone: switch (signal.tone) {
          _SignalTone.good => VeilBannerTone.good,
          _SignalTone.warn => VeilBannerTone.warn,
          _SignalTone.neutral => VeilBannerTone.info,
        },
        detail: signal.detail,
      ),
    );
  }
}

class _SecuritySignal {
  const _SecuritySignal({
    required this.label,
    required this.value,
    required this.detail,
    required this.tone,
  });

  final String label;
  final String value;
  final String detail;
  final _SignalTone tone;
}

enum _SignalTone { good, warn, neutral }
