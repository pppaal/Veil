import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session_state.dart';
import '../../../app/session/session_providers.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../application/contact_trust.dart';
import '../application/verified_accounts.dart';
import 'abuse_reports.dart';
import 'blocked_accounts.dart';
import 'contact_trust_store.dart';
import 'conversation_mutes.dart';
import 'group_leave.dart';

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

/// The accounts the user verified every device of, in memory for checks
/// that answer at once.
final verifiedAccountsProvider = ChangeNotifierProvider<VerifiedAccounts>((ref) {
  return VerifiedAccounts(ref.read(identityTrustProvider));
});

/// The trust layer before the messenger is attached to it: what
/// messengerControllerProvider wires its receipts, typing, fetches, sends
/// and notifications to, and attaches. Read [contactTrustProvider] instead.
final unattachedContactTrustProvider = Provider<ContactTrust>((ref) {
  final trust = ContactTrust(
    store: ContactTrustStore(ref.read(secureStorageProvider).scoped(SecureScope.conversationPolicy)),
    verified: ref.read(verifiedAccountsProvider),
  );
  // Forgotten at once on sign-out, before the wipe clears the stored document,
  // so no write still pending puts it back.
  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    if ((previous?.isAuthenticated ?? false) && !next.isAuthenticated) trust.forget();
  });
  ref.onDispose(trust.dispose);
  return trust;
});

/// Who each account is to this phone and which chats are message requests
/// (ContactTrust), with the messenger attached.
final contactTrustProvider = ChangeNotifierProvider<ContactTrust>((ref) {
  ref.read(messengerControllerProvider);
  return ref.read(unattachedContactTrustProvider);
});

/// Leaving a group from its message request bar.
final groupLeaveProvider = Provider<GroupLeave>((ref) {
  return GroupLeave(
    api: ref.read(apiClientProvider),
    accessToken: () => ref.read(appSessionProvider).accessToken,
    refreshConversations: () => ref.read(messengerControllerProvider).refreshConversations(),
  );
});
