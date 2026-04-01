import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
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
        value: session.deviceId == null ? 'Unbound' : _shortId(session.deviceId!),
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
        detail: 'Private device material stays on the device. The server never receives it.',
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasDeviceSecretRefs ? _SignalTone.good : _SignalTone.warn,
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
          data: (state) => state.biometricsAvailable ? 'Available' : 'Unavailable',
          orElse: () => 'Checking',
        ),
        detail: 'Device-level biometric unlock only. No remote fallback exists.',
        tone: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable ? _SignalTone.good : _SignalTone.neutral,
          orElse: () => _SignalTone.neutral,
        ),
      ),
    ];

    final runtimeSignals = <_SecuritySignal>[
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
        tone: messenger.realtimeConnected ? _SignalTone.good : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: 'Local cache',
        value: !cacheConfigured
            ? 'Disabled'
            : cacheReady
                ? 'Ready'
                : 'Starting',
        detail: !cacheConfigured
            ? 'Message cache stays off until encrypted-at-rest storage is integrated.'
            : 'Conversations and envelopes are cached locally behind the current alpha encrypted-at-rest layer.',
        tone: !cacheConfigured
            ? _SignalTone.warn
            : cacheReady
                ? _SignalTone.good
                : _SignalTone.neutral,
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
      _SecuritySignal(
        label: 'Crypto adapter',
        value: 'Mock active',
        detail: 'Dev-only opaque payloads are active. Audited production crypto is still required.',
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
                VeilStatusPill(label: 'Internal alpha'),
                VeilStatusPill(label: 'Mock crypto active', tone: VeilBannerTone.warn),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SecuritySection(title: 'Identity'),
          ...identitySignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: 16),
          const _SecuritySection(title: 'Runtime'),
          ...runtimeSignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: VeilSectionLabel(title.toUpperCase()),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({required this.signal});

  final _SecuritySignal signal;

  @override
  Widget build(BuildContext context) {
    final color = switch (signal.tone) {
      _SignalTone.good => const Color(0xFF8CB6FF),
      _SignalTone.warn => const Color(0xFFFFC670),
      _SignalTone.neutral => Theme.of(context).colorScheme.outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(signal.label, style: Theme.of(context).textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: 0.32)),
                  ),
                  child: Text(
                    signal.value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              signal.detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.76),
                  ),
            ),
          ],
        ),
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
