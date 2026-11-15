import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_adapter_registry.dart';
import '../../../core/network/pinned_http_client.dart' show parsePinList;
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../attachments/attachments_feature.dart';
import 'security_signal_rows.dart';

class SecurityStatusScreen extends ConsumerWidget {
  const SecurityStatusScreen({super.key, this.tlsPins = VeilConfig.tlsPins});

  /// The relay's TLS pins as this build sets them (VEIL_TLS_PINS).
  final String tlsPins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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

    // A fact read from this phone, or "Checking…" in muted type until it is.
    SecuritySignal local(String label, SecuritySignal Function(LocalSecuritySnapshot state) read) =>
        localSecurity.maybeWhen(
          data: read,
          orElse: () => SecuritySignal(label: label, value: l10n.securityStatusChecking, tone: SecuritySignalTone.neutral),
        );

    final thisPhone = <SecuritySignal>[
      local(
        l10n.securityStatusPin,
        (state) => SecuritySignal(
          label: l10n.securityStatusPin,
          value: state.hasPin ? l10n.securityStatusPinConfigured : l10n.securityStatusPinUnset,
          tone: state.hasPin ? SecuritySignalTone.good : SecuritySignalTone.neutral,
        ),
      ),
      local(
        l10n.securityStatusBiometrics,
        (state) => SecuritySignal(
          label: l10n.securityStatusBiometrics,
          value: state.biometricsAvailable ? l10n.securityStatusAvailable : l10n.securityStatusUnavailable,
          tone: state.biometricsAvailable ? SecuritySignalTone.good : SecuritySignalTone.neutral,
        ),
      ),
      local(
        l10n.securityStatusScreenCapture,
        (state) => !state.screenCaptureProtectionSupported
            ? SecuritySignal(
                label: l10n.securityStatusScreenCapture,
                value: l10n.securityStatusScreenCapturePlatformLimited,
                detail: l10n.securityStatusScreenCaptureUnsupportedDetail,
                tone: SecuritySignalTone.neutral,
              )
            : SecuritySignal(
                label: l10n.securityStatusScreenCapture,
                value: state.screenCaptureProtectionEnabled
                    ? l10n.securityStatusBlocked
                    : l10n.securityStatusScreenCaptureNotBlocked,
                tone: state.screenCaptureProtectionEnabled ? SecuritySignalTone.good : SecuritySignalTone.warn,
              ),
      ),
      local(
        l10n.securityStatusAppPreview,
        (state) => SecuritySignal(
          label: l10n.securityStatusAppPreview,
          value: state.appPreviewProtectionEnabled
              ? l10n.securityStatusAppPreviewProtected
              : l10n.securityStatusAppPreviewPartial,
          tone: state.appPreviewProtectionEnabled ? SecuritySignalTone.good : SecuritySignalTone.warn,
        ),
      ),
      local(
        l10n.securityStatusIntegrity,
        (state) => state.integrityCompromised
            ? SecuritySignal(
                label: l10n.securityStatusIntegrity,
                value: l10n.securityStatusIntegrityCompromised,
                detail: state.integrityReasons.isEmpty
                    ? l10n.securityStatusIntegrityCompromisedDetail
                    : l10n.securityStatusIntegrityCompromisedReasons(state.integrityReasons.join(' | ')),
                tone: SecuritySignalTone.danger,
              )
            : SecuritySignal(
                label: l10n.securityStatusIntegrity,
                value: l10n.securityStatusIntegrityClean,
                tone: SecuritySignalTone.good,
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

    final connection = <SecuritySignal>[
      // Whether this phone reaches the server: not configured, refused by
      // the build's own transport rules, connected, or not right now.
      SecuritySignal(
        label: l10n.securityStatusApiMode,
        value: !VeilConfig.hasApi
            ? l10n.securityStatusUnavailable
            : runtimeError != null
                ? l10n.securityStatusBlocked
                : messenger.realtimeConnected
                    ? l10n.securityStatusRelayConnected
                    : l10n.securityStatusIdle,
        // The configuration error is the build's own diagnostic, in English.
        detail: !VeilConfig.hasApi ? l10n.securityStatusApiUnavailableDetail : runtimeError,
        tone: !VeilConfig.hasApi || runtimeError != null
            ? SecuritySignalTone.warn
            : messenger.realtimeConnected
                ? SecuritySignalTone.good
                : SecuritySignalTone.neutral,
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
        label: l10n.securityStatusPushPayloads,
        value: VeilConfig.hasApi ? l10n.securityStatusPushPayloadsMetadata : l10n.securityStatusUnavailable,
        detail: VeilConfig.hasApi
            ? l10n.securityStatusPushPayloadsMetadataDetail
            : l10n.securityStatusPushPayloadsUnavailableDetail,
        tone: VeilConfig.hasApi ? SecuritySignalTone.good : SecuritySignalTone.neutral,
      ),
    ];

    final encryption = <SecuritySignal>[
      crypto,
      local(
        l10n.securityStatusSecretRefs,
        (state) => SecuritySignal(
          label: l10n.securityStatusSecretRefs,
          value: state.hasDeviceSecretRefs ? l10n.securityStatusSecretRefsPresent : l10n.securityStatusSecretRefsMissing,
          tone: state.hasDeviceSecretRefs ? SecuritySignalTone.good : SecuritySignalTone.warn,
        ),
      ),
      SecuritySignal(
        label: l10n.securityStatusLocalCache,
        value: !cacheConfigured
            ? l10n.securityStatusDisabled
            : cacheReady
                ? l10n.securityStatusReady
                : l10n.securityStatusStarting,
        detail: !cacheConfigured
            ? l10n.securityStatusLocalCacheDisabledDetail
            : cacheReady
                ? l10n.securityStatusLocalCacheDetail
                : null,
        tone: cacheConfigured && cacheReady ? SecuritySignalTone.good : SecuritySignalTone.neutral,
      ),
    ];

    // What never changes, as plain words: why is the Settings footer's,
    // said once there.
    final rules = <SecuritySignal>[
      SecuritySignal(label: l10n.securityStatusCloudBackup, value: l10n.commonNone, tone: SecuritySignalTone.neutral),
      SecuritySignal(
        label: l10n.securityStatusAccountRecovery,
        value: l10n.commonNone,
        tone: SecuritySignalTone.neutral,
      ),
      SecuritySignal(
        label: l10n.securityStatusDeviceTransfer,
        value: l10n.securityStatusDeviceTransferValue,
        tone: SecuritySignalTone.neutral,
      ),
      SecuritySignal(
        label: l10n.securityStatusLocalWipe,
        value: l10n.securityStatusLocalWipeValue,
        tone: SecuritySignalTone.neutral,
      ),
    ];

    // Four groups of rows, each fact once with its state as a word.
    return VeilShell(
      title: l10n.securityStatusTitle,
      grouped: true,
      child: ListView(
        padding: const EdgeInsets.only(bottom: VeilSpace.xl),
        children: [
          SecuritySignalGroup(title: l10n.securityGroupThisPhone, signals: thisPhone),
          SecuritySignalGroup(title: l10n.securityGroupConnection, signals: connection),
          SecuritySignalGroup(title: l10n.securityGroupEncryption, signals: encryption),
          SecuritySignalGroup(title: l10n.securityGroupRules, signals: rules),
        ],
      ),
    );
  }

  // What protects this build's messages, read from the adapter it runs:
  // the libsignal bridge and a development adapter must not be shown as
  // Veil's own ratchet.
  static SecuritySignal _cryptoSignal(AppLocalizations l10n, String adapterId) =>
      switch (cryptoAdapterKindOf(adapterId)) {
        CryptoAdapterKind.veilRatchet => SecuritySignal(
            label: l10n.securityStatusCryptoImplementation,
            value: l10n.securityStatusCryptoVeilRatchet,
            detail: l10n.securityStatusCryptoVeilRatchetDetail(adapterId),
            tone: SecuritySignalTone.neutral,
          ),
        CryptoAdapterKind.libsignal => SecuritySignal(
            label: l10n.securityStatusCryptoImplementation,
            value: l10n.securityStatusCryptoLibsignal,
            detail: l10n.securityStatusCryptoLibsignalDetail(adapterId),
            tone: SecuritySignalTone.neutral,
          ),
        CryptoAdapterKind.development => SecuritySignal(
            label: l10n.securityStatusCryptoImplementation,
            value: l10n.securityStatusCryptoDevelopment,
            detail: l10n.securityStatusCryptoDevelopmentDetail(adapterId),
            tone: SecuritySignalTone.warn,
          ),
      };
}
