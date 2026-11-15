import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_adapter_registry.dart';
import '../../../core/network/pinned_http_client.dart' show parsePinList;
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_screen_intro.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/attachments_feature.dart';
import 'security_signal_rows.dart';

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

    final identitySignals = <SecuritySignal>[
      SecuritySignal(
        label: l10n.securityStatusBoundDevice,
        value: session.deviceId == null ? l10n.securityStatusBoundDeviceUnbound : _shortId(session.deviceId!),
        detail: session.deviceId == null
            ? l10n.securityStatusBoundDeviceNoneDetail
            : l10n.securityStatusBoundDeviceDetail,
        tone: session.deviceId == null ? SecuritySignalTone.warn : SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusSecretRefs,
        value: localSecurity.maybeWhen(
          data: (state) =>
              state.hasDeviceSecretRefs ? l10n.securityStatusSecretRefsPresent : l10n.securityStatusSecretRefsMissing,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusSecretRefsDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasDeviceSecretRefs ? SecuritySignalTone.good : SecuritySignalTone.warn,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
      SecuritySignal(
        label: l10n.securityStatusPin,
        value: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? l10n.securityStatusPinConfigured : l10n.securityStatusPinUnset,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusPinDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.hasPin ? SecuritySignalTone.good : SecuritySignalTone.warn,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
      SecuritySignal(
        label: l10n.securityStatusBiometrics,
        value: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable ? l10n.securityStatusAvailable : l10n.securityStatusUnavailable,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusBiometricsDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.biometricsAvailable ? SecuritySignalTone.good : SecuritySignalTone.neutral,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
      SecuritySignal(
        label: l10n.securityStatusPrivacyShield,
        value: l10n.securityStatusEnabled,
        detail: l10n.securityStatusPrivacyShieldDetail,
        tone: SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusAppPreview,
        value: localSecurity.maybeWhen(
          data: (state) => state.appPreviewProtectionEnabled
              ? l10n.securityStatusAppPreviewProtected
              : l10n.securityStatusAppPreviewPartial,
          orElse: () => l10n.securityStatusChecking,
        ),
        detail: l10n.securityStatusAppPreviewDetail,
        tone: localSecurity.maybeWhen(
          data: (state) => state.appPreviewProtectionEnabled ? SecuritySignalTone.good : SecuritySignalTone.warn,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
      SecuritySignal(
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
              ? SecuritySignalTone.neutral
              : state.screenCaptureProtectionEnabled
                  ? SecuritySignalTone.good
                  : SecuritySignalTone.warn,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
      // About download tickets, which only a build with attachments issues.
      if (kAttachmentsEnabled)
        SecuritySignal(
          label: l10n.securityStatusClipboard,
          value: l10n.securityStatusClipboardRestricted,
          detail: l10n.securityStatusClipboardDetail,
          tone: SecuritySignalTone.good,
        ),
    ];

    final runtimeSignals = <SecuritySignal>[
      SecuritySignal(
        label: l10n.securityStatusTransport,
        value: runtimeError == null ? l10n.securityStatusTransportCompliant : l10n.securityStatusBlocked,
        // The configuration error is the build's own diagnostic, in English.
        detail: runtimeError ?? l10n.securityStatusTransportDetail,
        tone: runtimeError == null ? SecuritySignalTone.good : SecuritySignalTone.warn,
      ),
      SecuritySignal(
        label: l10n.securityStatusTlsPins,
        value: pinCount > 0 ? l10n.securityStatusTlsPinsPinned : l10n.securityStatusTlsPinsUnpinned,
        detail: pinCount > 0
            ? l10n.securityStatusTlsPinsPinnedDetail(pinCount)
            : l10n.securityStatusTlsPinsUnpinnedDetail,
        tone: pinCount > 0 ? SecuritySignalTone.good : SecuritySignalTone.warn,
      ),
      SecuritySignal(
        label: l10n.securityStatusApiMode,
        value: VeilConfig.hasApi ? l10n.securityStatusApiAttached : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi ? l10n.securityStatusApiAttachedDetail : l10n.securityStatusApiUnavailableDetail,
        tone: VeilConfig.hasApi ? SecuritySignalTone.good : SecuritySignalTone.warn,
      ),
      SecuritySignal(
        label: l10n.securityStatusRelayLink,
        value: messenger.realtimeConnected ? l10n.securityStatusRelayConnected : l10n.securityStatusIdle,
        detail: messenger.realtimeConnected
            ? l10n.securityStatusRelayConnectedDetail
            : l10n.securityStatusRelayIdleDetail,
        tone: messenger.realtimeConnected ? SecuritySignalTone.good : SecuritySignalTone.neutral,
      ),
      SecuritySignal(
        label: l10n.securityStatusLocalCache,
        value: !cacheConfigured
            ? l10n.securityStatusDisabled
            : cacheReady
                ? l10n.securityStatusReady
                : l10n.securityStatusStarting,
        detail: !cacheConfigured ? l10n.securityStatusLocalCacheDisabledDetail : l10n.securityStatusLocalCacheDetail,
        tone: !cacheConfigured
            ? SecuritySignalTone.warn
            : cacheReady
                ? SecuritySignalTone.good
                : SecuritySignalTone.neutral,
      ),
      SecuritySignal(
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
          data: (state) => state.integrityCompromised ? SecuritySignalTone.warn : SecuritySignalTone.good,
          orElse: () => SecuritySignalTone.neutral,
        ),
      ),
    ];

    final productSignals = <SecuritySignal>[
      SecuritySignal(
        label: l10n.securityStatusCloudBackup,
        value: l10n.securityStatusDisabled,
        detail: l10n.securityStatusCloudBackupDetail,
        tone: SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusAccountRecovery,
        value: l10n.securityStatusUnavailable,
        detail: l10n.securityStatusAccountRecoveryDetail,
        tone: SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusDeviceTransfer,
        value: l10n.securityStatusDeviceTransferValue,
        detail: l10n.securityStatusDeviceTransferDetail,
        tone: SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusLocalWipe,
        value: l10n.securityStatusAvailable,
        detail: l10n.securityStatusLocalWipeDetail,
        tone: SecuritySignalTone.good,
      ),
      crypto,
      SecuritySignal(
        label: l10n.securityStatusPushPlaintext,
        value: l10n.securityStatusPushPlaintextForbidden,
        detail: l10n.securityStatusPushPlaintextDetail,
        tone: SecuritySignalTone.good,
      ),
      SecuritySignal(
        label: l10n.securityStatusPushProvider,
        value: VeilConfig.hasApi ? l10n.securityStatusPushProviderSeam : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi
            ? l10n.securityStatusPushProviderSeamDetail
            : l10n.securityStatusPushProviderUnavailableDetail,
        tone: VeilConfig.hasApi ? SecuritySignalTone.warn : SecuritySignalTone.neutral,
      ),
      SecuritySignal(
        label: l10n.securityStatusPushPayloads,
        value: VeilConfig.hasApi ? l10n.securityStatusPushPayloadsMetadata : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi
            ? l10n.securityStatusPushPayloadsMetadataDetail
            : l10n.securityStatusPushPayloadsUnavailableDetail,
        tone: VeilConfig.hasApi ? SecuritySignalTone.good : SecuritySignalTone.neutral,
      ),
    ];

    final attention = [
      for (final signal in [...identitySignals, ...runtimeSignals, ...productSignals])
        if (signal.needsAttention) signal.label,
    ];

    // What needs a look comes first, then the facts in three groups of
    // rows. A wide window also keeps the build's marks and its three tiles.
    return VeilShell(
      title: l10n.securityStatusTitle,
      child: ListView(
        children: [
          VeilScreenIntro(
            title: l10n.securityStatusHeroTitle,
            body: l10n.securityStatusHeroBody,
          ),
          if (!context.veilPhoneWidth) ...[
            const SizedBox(height: VeilSpace.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.securityStatusPillPrivateBeta),
                VeilStatusPill(
                  label: crypto.value,
                  tone: crypto.needsAttention ? VeilBannerTone.warn : VeilBannerTone.info,
                ),
              ],
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
          ],
          if (attention.isNotEmpty) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              tone: VeilBannerTone.warn,
              title: l10n.securityStatusAttentionTitle(attention.length),
              message: attention.join(' · '),
            ),
          ],
          const SizedBox(height: VeilSpace.lg),
          SecuritySignalGroup(title: l10n.securityStatusSectionIdentity, signals: identitySignals),
          const SizedBox(height: VeilSpace.lg),
          SecuritySignalGroup(title: l10n.securityStatusSectionRuntime, signals: runtimeSignals),
          const SizedBox(height: VeilSpace.lg),
          SecuritySignalGroup(title: l10n.securityStatusSectionProductRules, signals: productSignals),
        ],
      ),
    );
  }

  // What protects this build's messages, read from the adapter it runs:
  // the libsignal bridge and a development adapter must not be shown as
  // VEIL's own ratchet.
  static SecuritySignal _cryptoSignal(AppLocalizations l10n, String adapterId) =>
      switch (cryptoAdapterKindOf(adapterId)) {
        CryptoAdapterKind.veilRatchet => SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoVeilRatchet,
            detail: l10n.securityStatusCryptoVeilRatchetDetail(adapterId),
            tone: SecuritySignalTone.neutral,
          ),
        CryptoAdapterKind.libsignal => SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoLibsignal,
            detail: l10n.securityStatusCryptoLibsignalDetail(adapterId),
            tone: SecuritySignalTone.neutral,
          ),
        CryptoAdapterKind.development => SecuritySignal(
            label: l10n.securityStatusCryptoAdapter,
            value: l10n.securityStatusCryptoDevelopment,
            detail: l10n.securityStatusCryptoDevelopmentDetail(adapterId),
            tone: SecuritySignalTone.warn,
          ),
      };

  static String _shortId(String value) {
    if (value.length <= 12) {
      return value;
    }

    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }
}
