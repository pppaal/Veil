import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session_state.dart';
import '../../../app/session/session_providers.dart';
import 'device_transfer_controller.dart';

/// The old device's transfer state for the app's life: read, not watched,
/// so neither a token refresh nor the cache opening rebuilds it mid-transfer.
final deviceTransferControllerProvider = ChangeNotifierProvider<DeviceTransferController>((ref) {
  final controller = DeviceTransferController(
    apiClient: ref.read(apiClientProvider),
    session: () => ref.read(appSessionProvider),
    onSecurityException: (error) => ref.read(appSessionProvider.notifier).handleSecurityException(error),
  );
  // A transfer belongs to the identity that opened it.
  ref.listen<AppSessionState>(appSessionProvider, (_, next) {
    if (!next.isAuthenticated) controller.clearTransferState();
  });
  return controller;
});
