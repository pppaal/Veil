import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

void main() {
  test(
      'device_not_active clears session, secrets, pin, and cache while preserving onboarding',
      () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final cache = _MemoryConversationCache();
    final tempStore = _MemoryAttachmentTempFileStore();
    final controller = AppSessionController(
      storage,
      VeilApiClient(baseUrl: 'http://localhost:3000/v1'),
      createDefaultCryptoAdapter(),
      cacheService: cache,
      attachmentTempFileStore: tempStore,
    );

    await storage.persistOnboardingAccepted(true);
    await storage.persistPin('123456');
    await storage.persistDeviceSecretRefs(
      identityPrivateRef: 'secure-store://identity',
      authPrivateKey: 'auth-private',
      authPublicKey: 'auth-public',
    );
    await storage.persistSession(
      accessToken: 'token',
      userId: 'user-1',
      deviceId: 'device-1',
      handle: 'atlas',
      displayName: 'Atlas',
    );
    await storage.readOrCreateCacheKey();

    await controller.bootstrap();
    final handled = await controller.handleSecurityException(
      VeilApiException(
        'This device is no longer the active VEIL device.',
        code: 'device_not_active',
        statusCode: 401,
      ),
    );

    expect(handled, isTrue);
    expect(controller.state.isAuthenticated, isFalse);
    expect(controller.state.onboardingAccepted, isTrue);
    expect(await storage.hasPin(), isFalse);
    expect(await storage.hasDeviceSecretRefs(), isFalse);
    expect(cache.clearAllCalls, 1);
    expect(tempStore.purgeAllCalls, 1);
  });

  test('explicit local wipe clears onboarding and local barrier', () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final controller = AppSessionController(
      storage,
      VeilApiClient(baseUrl: 'http://localhost:3000/v1'),
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );

    await storage.persistOnboardingAccepted(true);
    await storage.persistPin('123456');
    await storage.persistSession(
      accessToken: 'token',
      userId: 'user-1',
      deviceId: 'device-1',
      handle: 'atlas',
    );

    await controller.bootstrap();
    await controller.wipeLocalDeviceState();

    expect(controller.state.isAuthenticated, isFalse);
    expect(controller.state.onboardingAccepted, isFalse);
    expect(await storage.hasPin(), isFalse);
    expect(await storage.readOnboardingAccepted(), isFalse);
  });

  test(
      'registerAndAuthenticate persists a bound session and local device secrets',
      () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final api = _FakeSessionApiClient();
    final controller = AppSessionController(
      storage,
      api,
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );

    await controller.registerAndAuthenticate(
      handle: 'atlas',
      displayName: 'Atlas',
    );

    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.state.handle, 'atlas');
    expect(controller.state.deviceId, 'device-registered');
    expect(controller.state.authFlowStage, AuthFlowStage.complete);
    expect(await storage.hasDeviceSecretRefs(), isTrue);
    expect(await storage.readSession(), isNotNull);
    expect(api.registerCalls, hasLength(1));
    expect(api.challengeDeviceIds, contains('device-registered'));
    expect(api.verifyDeviceIds, contains('device-registered'));
  });

  test(
      'claimTransfer and completeTransferAndAuthenticate bind the new active device',
      () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final api = _FakeSessionApiClient();
    final controller = AppSessionController(
      storage,
      api,
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );

    final claim = await controller.claimTransfer(
      sessionId: 'session-1',
      transferToken: 'token-1',
      deviceName: 'VEIL Beta Device',
    );

    expect(claim.claimId, 'claim-1');
    expect(claim.claimantFingerprint, 'FPR-ALPHA');

    await controller.completeTransferAndAuthenticate(
      sessionId: 'session-1',
      transferToken: 'token-1',
      claimId: claim.claimId,
    );

    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.state.deviceId, 'device-transferred');
    expect(controller.state.handle, 'atlas');
    expect(await storage.hasDeviceSecretRefs(), isTrue);
    expect(await storage.readSession(), isNotNull);
  });

  test(
      'transfer failure clears the pending claim and requires a fresh registration',
      () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final api = _FakeSessionApiClient()
      ..completeTransferError = VeilApiException(
        'This new device could not prove the final transfer handoff.',
        code: 'transfer_completion_invalid',
        statusCode: 401,
      );
    final controller = AppSessionController(
      storage,
      api,
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );

    final claim = await controller.claimTransfer(
      sessionId: 'session-1',
      transferToken: 'token-1',
      deviceName: 'VEIL Beta Device',
    );

    await expectLater(
      controller.completeTransferAndAuthenticate(
        sessionId: 'session-1',
        transferToken: 'token-1',
        claimId: claim.claimId,
      ),
      throwsA(isA<VeilApiException>()),
    );

    expect(
      controller.state.errorMessage,
      'This new device could not prove the final transfer handoff.',
    );

    await expectLater(
      controller.completeTransferAndAuthenticate(
        sessionId: 'session-1',
        transferToken: 'token-1',
        claimId: claim.claimId,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String?> values = <String, String?>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}

class _MemoryConversationCache implements ConversationCacheService {
  int clearAllCalls = 0;

  @override
  Future<void> clearAll() async {
    clearAllCalls += 1;
  }

  @override
  Future<void> purgeExpiredMessages() async {}

  @override
  Future<List<ConversationPreview>> readConversations() async => const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async =>
      const [];

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<ConversationPagingState> readPagingState(
          String conversationId) async =>
      const ConversationPagingState();

  @override
  Future<void> removePendingMessage(String clientMessageId) async {}

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {}

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async =>
      const [];

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async =>
      const MessageSearchPage(items: <MessageSearchResult>[]);

  @override
  Future<void> storeConversations(
      List<ConversationPreview> conversations) async {}

  @override
  Future<void> storeMessages(
      String conversationId, List<ChatMessage> messages) async {}

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {}

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {}
}

class _FakeSessionApiClient extends VeilApiClient {
  _FakeSessionApiClient() : super(baseUrl: 'http://localhost:3000/v1');

  final List<Map<String, dynamic>> registerCalls = <Map<String, dynamic>>[];
  final List<String> challengeDeviceIds = <String>[];
  final List<String> verifyDeviceIds = <String>[];
  VeilApiException? completeTransferError;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    registerCalls.add(body);
    return {
      'deviceId': 'device-registered',
    };
  }

  @override
  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) async {
    challengeDeviceIds.add(body['deviceId'] as String);
    return {
      'challengeId': 'challenge-${challengeDeviceIds.length}',
      'challenge': 'opaque-challenge-${challengeDeviceIds.length}',
    };
  }

  @override
  Future<Map<String, dynamic>> verify(Map<String, dynamic> body) async {
    verifyDeviceIds.add(body['deviceId'] as String);
    final deviceId = body['deviceId'] as String;
    return {
      'accessToken': 'token-for-$deviceId',
      'userId': 'user-atlas',
      'deviceId': deviceId,
    };
  }

  @override
  Future<Map<String, dynamic>> claimTransfer(Map<String, dynamic> body) async {
    return {
      'claimId': 'claim-1',
      'claimantFingerprint': 'FPR-ALPHA',
      'expiresAt': DateTime.utc(2026, 4, 1, 12, 5, 0).toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> completeTransfer(
      Map<String, dynamic> body) async {
    final error = completeTransferError;
    if (error != null) {
      throw error;
    }

    return {
      'newDeviceId': 'device-transferred',
      'handle': 'atlas',
      'displayName': 'Atlas',
    };
  }
}

class _MemoryAttachmentTempFileStore implements AttachmentTempFileStore {
  int purgeAllCalls = 0;

  @override
  Future<void> cleanupOrphanedFiles({
    Iterable<String> keepPaths = const <String>[],
    Duration maxAge = DefaultAttachmentTempFileStore.defaultMaxAge,
    int maxFileCount = DefaultAttachmentTempFileStore.defaultMaxFileCount,
  }) async {}

  @override
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  }) async {
    return AttachmentTempBlob(
      path: existingPath ?? 'temp://$filename',
      filename: filename,
      sizeBytes: sizeBytes,
      sha256: 'sha256-$filename',
      createdAt: DateTime.utc(2026, 4, 1),
    );
  }

  @override
  Future<void> deleteTempFile(String? path) async {}

  @override
  Future<void> purgeAll() async {
    purgeAllCalls += 1;
  }
}
