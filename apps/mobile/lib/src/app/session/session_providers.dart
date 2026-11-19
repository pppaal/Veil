import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/veil_config.dart';
import '../../core/di/core_providers.dart';
import '../../core/network/pinned_http_client.dart';
import '../../core/network/veil_api_client.dart';
import '../../core/notifications/push_token_coordinator.dart';
import '../../core/notifications/remote_push_service.dart';
import '../../features/attachments/data/attachment_providers.dart';
import '../app_session_state.dart';
import 'app_session_controller.dart';

// Explicit variable type: apiClientProvider and appSessionProvider refer
// to each other, so the analyzer cannot infer their top-level types
// without this annotation (top_level_cycle).
final Provider<VeilApiClient> apiClientProvider = Provider<VeilApiClient>((ref) {
  final pins = parsePinList(VeilConfig.tlsPins);
  final httpClient = buildPinnedHttpClient(allowedFingerprints: pins);
  return VeilApiClient(
    baseUrl: VeilConfig.apiBaseUrl,
    client: httpClient,
    // Resolved lazily so the api client and session controller can refer to
    // each other without a Riverpod cycle. Returns null when there is no
    // refresh token, which keeps the original 401 surface to the caller.
    tokenRefresher: () => ref.read(appSessionProvider.notifier).refreshSession(),
  );
});

final StateNotifierProvider<AppSessionController, AppSessionState>
    appSessionProvider =
    StateNotifierProvider<AppSessionController, AppSessionState>((ref) {
  return AppSessionController(
    ref.read(secureStorageProvider),
    ref.read(apiClientProvider),
    ref.read(cryptoAdapterProvider),
    // Read, not watched: the session controller outlives every database.
    cacheService: ref.read(cacheHandleProvider),
    attachmentTempFileStore: ref.read(attachmentTempFileStoreProvider),
    onLocalCacheMaterialChanged: () {
      ref.read(cacheEpochProvider.notifier).state++;
      ref.invalidate(conversationCacheProvider);
    },
  );
});

final pushTokenCoordinatorProvider = Provider<PushTokenCoordinator>((ref) {
  final coordinator = PushTokenCoordinator(
    apiClient: ref.read(apiClientProvider),
    pushService: ref.read(remotePushServiceProvider),
  );
  ref.onDispose(() {
    unawaited(coordinator.dispose());
  });
  return coordinator;
});
