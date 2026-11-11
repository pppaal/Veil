import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/session_policy.dart';

ConversationSessionState _session({
  String remoteDeviceId = 'dev-selene',
  String localDeviceId = 'dev-local',
  String remoteIdentityPublicKey = 'ik-selene',
}) {
  return ConversationSessionState(
    sessionLocator: 'session://conv-1',
    sessionEnvelopeVersion: 'veil-envelope-v1',
    requiresLocalPersistence: true,
    sessionSchemaVersion: 3,
    localDeviceId: localDeviceId,
    remoteDeviceId: remoteDeviceId,
    remoteIdentityFingerprint: 'fp',
    bootstrappedAt: DateTime.utc(2026, 4, 1),
    remoteIdentityPublicKey: remoteIdentityPublicKey,
  );
}

KeyBundle _bundle({String deviceId = 'dev-selene', String identityPublicKey = 'ik-selene'}) {
  return KeyBundle(
    userId: 'user-selene',
    deviceId: deviceId,
    handle: 'selene',
    identityPublicKey: identityPublicKey,
    signedPrekeyBundle: 'spk',
  );
}

ConversationPreview _conversation({ConversationSessionState? session, String deviceId = ''}) {
  return ConversationPreview(
    id: 'conv-1',
    peerHandle: 'selene',
    peerDisplayName: null,
    recipientBundle: _bundle(deviceId: deviceId),
    lastEnvelope: null,
    updatedAt: DateTime.utc(2026, 4, 1),
    sessionState: session,
  );
}

SessionDecision _decide({
  bool engineHasSession = true,
  ConversationSessionState? session,
  KeyBundle? bundle,
}) {
  return decideSession(
    engineHasSession: engineHasSession,
    session: session,
    localDeviceId: 'dev-local',
    bundle: bundle ?? _bundle(),
  );
}

void main() {
  group('decideSession', () {
    test('bootstraps only when the engine has no session', () {
      expect(_decide(engineHasSession: false, session: _session()).action, SessionAction.bootstrap);
    });

    test('reuses a live session for the same device', () {
      final decision = _decide(session: _session());
      expect(decision.action, SessionAction.reuse);
      expect(decision.identityMismatch, isFalse);
    });

    test('reuses an engine session the preview never recorded', () {
      expect(_decide(session: null).action, SessionAction.reuse);
    });

    test('a changed remote device bootstraps', () {
      expect(
        _decide(session: _session(), bundle: _bundle(deviceId: 'dev-selene-2')).action,
        SessionAction.bootstrap,
      );
    });

    test('a session recorded for another local device bootstraps', () {
      expect(
        _decide(session: _session(localDeviceId: 'dev-old-phone')).action,
        SessionAction.bootstrap,
      );
    });

    test('a new identity key on the same device keeps the session and flags it', () {
      final decision = _decide(
        session: _session(),
        bundle: _bundle(identityPublicKey: 'ik-impostor'),
      );
      expect(decision.action, SessionAction.reuse);
      expect(decision.identityMismatch, isTrue);
    });

    test('a new identity key for the pinned device is flagged even when a bootstrap is unavoidable', () {
      final decision = _decide(
        engineHasSession: false,
        session: _session(),
        bundle: _bundle(identityPublicKey: 'ik-impostor'),
      );
      expect(decision.action, SessionAction.bootstrap);
      expect(decision.identityMismatch, isTrue);
    });

    test('a bootstrap to a different device is not an identity mismatch', () {
      final decision = _decide(
        engineHasSession: false,
        session: _session(),
        bundle: _bundle(deviceId: 'dev-selene-2', identityPublicKey: 'ik-selene-2'),
      );
      expect(decision.action, SessionAction.bootstrap);
      expect(decision.identityMismatch, isFalse);
    });

    test('a session without a recorded identity key cannot be compared', () {
      final decision = _decide(
        session: _session(remoteIdentityPublicKey: ''),
        bundle: _bundle(identityPublicKey: 'ik-anything'),
      );
      expect(decision.identityMismatch, isFalse);
    });
  });

  group('keepSession', () {
    test('pins the served identity key on a session that has none yet', () {
      final conversation = _conversation(session: _session(remoteIdentityPublicKey: ''));
      final served = _bundle(deviceId: 'dev-selene', identityPublicKey: 'ik-selene');

      final kept = keepSession(conversation, served, _decide(session: conversation.sessionState, bundle: served));

      expect(kept.sessionState!.remoteIdentityPublicKey, 'ik-selene');
      expect(kept.sessionState!.sessionLocator, 'session://conv-1');
      expect(kept.recipientBundle, same(served));
      expect(kept.identityMismatchPending, isFalse);
    });

    test('a different key for the bound device flags and keeps the pinned bundle', () {
      final conversation = _conversation(session: _session(), deviceId: 'dev-selene');
      final served = _bundle(identityPublicKey: 'ik-impostor');

      final kept = keepSession(conversation, served, _decide(session: conversation.sessionState, bundle: served));

      expect(kept.identityMismatchPending, isTrue);
      expect(kept.recipientBundle, same(conversation.recipientBundle));
      expect(kept.sessionState!.remoteIdentityPublicKey, 'ik-selene');
    });

    test('an engine session the preview never recorded takes the served bundle', () {
      final conversation = _conversation();
      final served = _bundle(deviceId: 'dev-selene');

      final kept = keepSession(conversation, served, _decide(bundle: served));

      expect(kept.sessionState, isNull);
      expect(kept.recipientBundle, same(served));
    });
  });

  group('comesFromNewPeerDevice', () {
    CryptoEnvelope frameFrom(String senderDeviceId) => CryptoEnvelope(
          version: 'veil-envelope-v1',
          conversationId: 'conv-1',
          senderDeviceId: senderDeviceId,
          recipientUserId: 'user-local',
          ciphertext: 'c',
          nonce: 'n',
          messageKind: MessageKind.text,
        );

    test('a frame from another peer device signals a move', () {
      expect(
        comesFromNewPeerDevice(_conversation(session: _session()), frameFrom('dev-selene-2'), localDeviceId: 'dev-local'),
        isTrue,
      );
    });

    test('frames from the bound device, from this device or without a session do not', () {
      final conversation = _conversation(session: _session());
      expect(comesFromNewPeerDevice(conversation, frameFrom('dev-selene'), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(conversation, frameFrom('dev-local'), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(conversation, frameFrom(''), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(_conversation(), frameFrom('dev-selene-2'), localDeviceId: 'dev-local'), isFalse);
    });

    test('group frames never do', () {
      final group = _conversation(session: _session()).copyWith(type: ConversationType.group);
      expect(comesFromNewPeerDevice(group, frameFrom('dev-selene-2'), localDeviceId: 'dev-local'), isFalse);
    });
  });

  test('sessionStateFromMaterial records the identity key it was bootstrapped with', () {
    const material = SessionBootstrapMaterial(
      sessionLocator: 'session://conv-1',
      sessionEnvelopeVersion: 'veil-envelope-v1',
      requiresLocalPersistence: true,
      sessionSchemaVersion: 3,
      localDeviceId: 'dev-local',
      remoteDeviceId: 'dev-selene',
      remoteIdentityFingerprint: 'fp',
      auditHint: 'hint',
    );

    final state = sessionStateFromMaterial(material, remoteIdentityPublicKey: 'ik-selene');

    expect(state.remoteIdentityPublicKey, 'ik-selene');
    expect(state.remoteDeviceId, 'dev-selene');
    expect(state.sessionSchemaVersion, 3);
    expect(state.auditHint, 'hint');
  });
}
