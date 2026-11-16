import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session_state.dart';
import '../../../app/session/session_providers.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'abuse_reports.dart';
import 'blocked_accounts.dart';
import 'conversation_mutes.dart';

/// The accounts the user blocked, read from the server when the account
/// signs in and again at each unlock (a read that failed offline, or a
/// change made elsewhere, is caught up then), and forgotten when it signs
/// out.
final blockedAccountsProvider = ChangeNotifierProvider<BlockedAccounts>((ref) {
  final blocked = BlockedAccounts(
    api: ref.read(apiClientProvider),
    accessToken: () => ref.read(appSessionProvider).accessToken,
  );
  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    final wasSignedIn = previous?.isAuthenticated ?? false;
    if (!next.isAuthenticated) {
      if (wasSignedIn) blocked.clear();
      return;
    }
    final unlocked = (previous?.locked ?? true) && !next.locked;
    if (!wasSignedIn || unlocked) unawaited(blocked.refresh());
  });
  if (ref.read(appSessionProvider).isAuthenticated) unawaited(blocked.refresh());
  return blocked;
});

/// The chats muted on this phone, kept in the keystore, and forgotten (in
/// memory too) when the account signs out or the device is wiped.
final conversationMutesProvider = ChangeNotifierProvider<ConversationMutes>((ref) {
  final mutes = ConversationMutes(
    store: ref.read(secureStorageProvider).scoped(SecureScope.notifications),
    api: ref.read(apiClientProvider),
    accessToken: () => ref.read(appSessionProvider).accessToken,
  );
  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    if (previous?.isAuthenticated == next.isAuthenticated) return;
    if (next.isAuthenticated) {
      unawaited(mutes.load());
    } else {
      unawaited(mutes.clear());
    }
  });
  unawaited(mutes.load());
  return mutes;
});

final abuseReportsProvider = Provider<AbuseReports>((ref) {
  return AbuseReports(
    api: ref.read(apiClientProvider),
    accessToken: () => ref.read(appSessionProvider).accessToken,
  );
});
