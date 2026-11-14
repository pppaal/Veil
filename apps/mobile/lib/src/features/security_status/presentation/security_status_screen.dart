import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_adapter_registry.dart';
import '../../../core/network/pinned_http_client.dart' show parsePinList;
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SecurityStatusScreen extends ConsumerWidget {
  const SecurityStatusScreen({super.key, this.tlsPins = VeilConfig.tlsPins});

  /// The relay's TLS pins as this build sets them (VEIL_TLS_PINS).
  final String tlsPins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final messenger = ref.watch(messengerControllerProvider);
    final localSecurity = ref.watch(localSecuritySnapshotProvider);
    final crypto = _cryptoSignal(l10n, ref.watch(cryptoAdapterProvider).adapterId);
    final pinCount = parsePinList(tlsPins).length;
    final runtimeError = VeilConfig.runtimeConfigurationError;
    final cacheConfigured = VeilConfig.enableLocalCache;
    final cacheReady = ref.watch(conversationCacheProvider).maybeWhen(
          data: (cache) => cache != null,
          orElse: () => false,
        );

    final identitySignals = <_SecuritySignal>[
      _SecuritySignal(
        label: l10n.securityStatusBoundDevice,
        value: session.deviceId == null ? l10n.securityStatusBoundDeviceUnbound : _shortId(session.deviceId!),
        detail: session.deviceId == null
            ? l10n.securityStatusBoundDeviceNoneDetail
            : l10n.securityStatusBoundDeviceDetail,
        tone: session.deviceId == null ? _SignalTone.warn : _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusSecretRefs,
        value: localSecurity.maybeWhen(
          data: (state) =>
              state.hasDeviceSecretRefs ? l10n.securityStatusSecretRefsPresent : l10n.securityStatusSecretRefsMissing,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusSecretRefsDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasDeviceSecretRefs ? _SignalTone.good : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: l10n.securityStatusPin,
        value: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? l10n.securityStatusPinConfigured : l10n.securityStatusPinUnset,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusPinDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? _SignalTone.good : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: l10n.securityStatusBiometrics,
        value: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable ? l10n.securityStatusAvailable : l10n.securityStatusUnavailable,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusBiometricsDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable ? _SignalTone.good : _SignalTone.neutral,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: l10n.securityStatusPrivacyShield,
        value: l10n.securityStatusEnabled,
        detail: l10n.securityStatusPrivacyShieldDetail,
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusAppPreview,
        value: localSecurity.maybeWhen(
          data: (state) => state.appPreviewProtectionEnabled
              ? l10n.securityStatusAppPreviewProtected
              : l10n.securityStatusAppPreviewPartial,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusAppPreviewDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.appPreviewProtectionEnabled ? _SignalTone.good : _SignalTone.warn,
          orElse: () => _SignalTone.neutral,
        ),
      ),
      _SecuritySignal(
        label: l10n.securityStatusScreenCapture,
        value: localSecurity.maybeWhen(
          data: (state) => !state.screenCaptureProtectionSupported
              ? l10n.securityStatusScreenCapturePlatformLimited
              : state.screenCaptureProtectionEnabled
                  ? l10n.securityStatusBlocked
                  : l10n.securityStatusScreenCaptureNotBlocked,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: localSecurity.maybeWhen(
          data: (state) => state.screenCaptureProtectionSupported
              ? l10n.securityStatusScreenCaptureSupportedDetail
              : l10n.securityStatusScreenCaptureUnsupportedDetail,
          orElse: () => l10n.securityStatusScreenCaptureCheckingDetail,
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
      _SecuritySignal(
        label: l10n.securityStatusClipboard,
        value: l10n.securityStatusClipboardRestricted,
        detail: l10n.securityStatusClipboardDetail,
        tone: _SignalTone.good,
      ),
    ];

    final runtimeSignals = <_SecuritySignal>[
      _SecuritySignal(
        label: l10n.securityStatusTransport,
        value: runtimeError == null ? l10n.securityStatusTransportCompliant : l10n.securityStatusBlocked,
        // The configuration error is the build's own diagnostic, in English.
        detail: runtimeError ?? l10n.securityStatusTransportDetail,
        tone: runtimeError == null ? _SignalTone.good : _SignalTone.warn,
      ),
      _SecuritySignal(
        label: l10n.securityStatusTlsPins,
        value: pinCount > 0 ? l10n.securityStatusTlsPinsPinned : l10n.securityStatusTlsPinsUnpinned,
        detail: pinCount > 0
            ? l10n.securityStatusTlsPinsPinnedDetail(pinCount)
            : l10n.securityStatusTlsPinsUnpinnedDetail,
        tone: pinCount > 0 ? _SignalTone.good : _SignalTone.warn,
      ),
      _SecuritySignal(
        label: l10n.securityStatusApiMode,
        value: VeilConfig.hasApi ? l10n.securityStatusApiAttached : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi ? l10n.securityStatusApiAttachedDetail : l10n.securityStatusApiUnavailableDetail,
        tone: VeilConfig.hasApi ? _SignalTone.good : _SignalTone.warn,
      ),
      _SecuritySignal(
        label: l10n.securityStatusRelayLink,
        value: messenger.realtimeConnected ? l10n.securityStatusRelayConnected : l10n.securityStatusIdle,
        detail: messenger.realtimeConnected
            ? l10n.securityStatusRelayConnectedDetail
            : l10n.securityStatusRelayIdleDetail,
        tone: messenger.realtimeConnected ? _SignalTone.good : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: l10n.securityStatusLocalCache,
        value: !cacheConfigured
            ? l10n.securityStatusDisabled
            : cacheReady
                ? l10n.securityStatusReady
                : l10n.securityStatusStarting,
        detail: !cacheConfigured ? l10n.securityStatusLocalCacheDisabledDetail : l10n.securityStatusLocalCacheDetail,
        tone: !cacheConfigured
            ? _SignalTone.warn
            : cacheReady
                ? _SignalTone.good
                : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: l10n.securityStatusIntegrity,
        value: localSecurity.maybeWhen(
          data: (state) =>
              state.integrityCompromised ? l10n.securityStatusIntegrityCompromised : l10n.securityStatusIntegrityClean,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: localSecurity.maybeWhen(
          data: (state) => state.integrityCompromised
              ? state.integrityReasons.isEmpty
                  ? l10n.securityStatusIntegrityCompromisedDetail
                  : l10n.securityStatusIntegrityCompromisedReasons(state.integrityReasons.join(' | '))
              : l10n.securityStatusIntegrityCleanDetail,
          orElse: () => l10n.securityStatusIntegrityCheckingDetail,
        ),
        tone: localSecurity.maybeWhen(
          data: (state) => state.integrityCompromised ? _SignalTone.warn : _SignalTone.good,
          orElse: () => _SignalTone.neutral,
        ),
      ),
    ];

    final productSignals = <_SecuritySignal>[
      _SecuritySignal(
        label: l10n.securityStatusCloudBackup,
        value: l10n.securityStatusDisabled,
        detail: l10n.securityStatusCloudBackupDetail,
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusAccountRecovery,
        value: l10n.securityStatusUnavailable,
        detail: l10n.securityStatusAccountRecoveryDetail,
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusDeviceTransfer,
        value: l10n.securityStatusDeviceTransferValue,
        detail: l10n.securityStatusDeviceTransferDetail,
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusLocalWipe,
        value: l10n.securityStatusAvailable,
        detail: l10n.securityStatusLocalWipeDetail,
        tone: _SignalTone.good,
      ),
      crypto,
      _SecuritySignal(
        label: l10n.securityStatusPushPlaintext,
        value: l10n.securityStatusPushPlaintextForbidden,
        detail: l10n.securityStatusPushPlaintextDetail,
        tone: _SignalTone.good,
      ),
      _SecuritySignal(
        label: l10n.securityStatusPushProvider,
        value: VeilConfig.hasApi ? l10n.securityStatusPushProviderSeam : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi
            ? l10n.securityStatusPushProviderSeamDetail
            : l10n.securityStatusPushProviderUnavailableDetail,
        tone: VeilConfig.hasApi ? _SignalTone.warn : _SignalTone.neutral,
      ),
      _SecuritySignal(
        label: l10n.securityStatusPushPayloads,
        value: VeilConfig.hasApi ? l10n.securityStatusPushPayloadsMetadata : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi
            ? l10n.securityStatusPushPayloadsMetadataDetail
            : l10n.securityStatusPushPayloadsUnavailableDetail,
        tone: VeilConfig.hasApi ? _SignalTone.good : _SignalTone.neutral,
      ),
    ];

    return VeilShell(
      title: l10n.securityStatusTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.securityStatusEyebrow,
            title: l10n.securityStatusHeroTitle,
            body: l10n.securityStatusHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.securityStatusPillPrivateBeta),
                VeilStatusPill(
                  label: crypto.value,
                  tone: crypto.tone == _SignalTone.warn ? VeilBannerTone.warn : VeilBannerTone.info,
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(
                label: l10n.securityStatusMetricRuntime,
                value: runtimeError == null ? l10n.securityStatusReady : l10n.securityStatusBlocked,
              ),
              VeilMetricItem(
                label: l10n.securityStatusMetricRelay,
                value: messenger.realtimeConnected ? l10n.securityStatusMetricRelayLinked : l10n.securityStatusIdle,
              ),
              VeilMetricItem(
                label: l10n.securityStatusMetricCache,
                value: !cacheConfigured
                    ? l10n.securityStatusMetricCacheOff
                    : cacheReady
                        ? l10n.securityStatusReady
                        : l10n.securityStatusStarting,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          _SecuritySection(title: l10n.securityStatusSectionIdentity),
          ...identitySignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: VeilSpace.md),
          _SecuritySection(title: l10n.securityStatusSectionRuntime),
          ...runtimeSignals.map((signal) => _SecurityRow(signal: signal)),
          const SizedBox(height: VeilSpace.md),
          _SecuritySection(title: l10n.securityStatusSectionProductRules),
          ...productSignals.map((signal) => _SecurityRow(signal: signal)),
        ],
      ),
    );
  }

  // What protects this build's messages, read from the adapter it runs:
  // the libsignal bridge and a development adapter must not be shown as
  // VEIL's own ratchet.
  static _SecuritySignal _cryptoSignal(AppLocalizations l10n, String adapterId) =>
      switch (cryptoAdapterKindOf(adapterId)) {
        CryptoAdapterKind.veilRatchet => _SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoVeilRatchet,
            detail: l10n.securityStatusCryptoVeilRatchetDetail(adapterId),
            tone: _SignalTone.neutral,
          ),
        CryptoAdapterKind.libsignal => _SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoLibsignal,
            detail: l10n.securityStatusCryptoLibsignalDetail(adapterId),
            tone: _SignalTone.neutral,
          ),
        CryptoAdapterKind.development => _SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoDevelopment,
            detail: l10n.securityStatusCryptoDevelopmentDetail(adapterId),
            tone: _SignalTone.warn,
          ),
      };

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
