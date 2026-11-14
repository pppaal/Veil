import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_merge.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';

ConversationSessionState _session() => ConversationSessionState(
      sessionLocator: 'session://conv-1',
      sessionEnvelopeVersion: 'veil-envelope-v1',
      requiresLocalPersistence: true,
      sessionSchemaVersion: 3,
      localDeviceId: 'dev-local',
      remoteDeviceId: 'dev-selene',
      remoteIdentityFingerprint: 'fp',
      bootstrappedAt: DateTime.utc(2026, 4, 1),
      remoteIdentityPublicKey: 'ik-selene',
    );

const _fullBundle = KeyBundle(
  userId: 'user-selene',
  deviceId: 'dev-selene',
  handle: 'selene',
  identityPublicKey: 'ik-selene',
  signedPrekeyBundle: 'spk-selene',
);

// What the conversations API yields: the peer's user id and nothing else.
const _serverBundle = KeyBundle(
  userId: 'user-selene',
  deviceId: '',
  handle: 'selene',
  identityPublicKey: '',
  signedPrekeyBundle: '',
);

ConversationPreview _preview({
  String id = 'conv-1',
  KeyBundle bundle = _serverBundle,
  ConversationSessionState? session,
  int? timer,
  DateTime? updatedAt,
}) {
  return ConversationPreview(
    id: id,
    peerHandle: bundle.handle,
    peerDisplayName: 'Selene',
    recipientBundle: bundle,
    lastEnvelope: null,
    updatedAt: updatedAt ?? DateTime.utc(2026, 4, 1),
    sessionState: session,
    disappearingTimerSeconds: timer,
  );
}

void main() {
  test('keeps the local session and bundle when the server has none', () {
    final local = _preview(bundle: _fullBundle, session: _session());

    final merged = mergeConversationPreviews([local], [_preview()]).single;

    expect(merged.sessionState, same(local.sessionState));
    expect(merged.recipientBundle, same(_fullBundle));
  });

  test('takes everything else from the server', () {
    final local = _preview(bundle: _fullBundle, session: _session(), timer: 30);
    final server = _preview(timer: 300, updatedAt: DateTime.utc(2026, 4, 2));

    final merged = mergeConversationPreviews([local], [server]).single;

    expect(merged.disappearingTimerSeconds, 300);
    expect(merged.updatedAt, DateTime.utc(2026, 4, 2));
  });

  test('a server bundle with key material replaces the local one', () {
    const rotated = KeyBundle(
      userId: 'user-selene',
      deviceId: 'dev-selene-2',
      handle: 'selene',
      identityPublicKey: 'ik-selene-2',
      signedPrekeyBundle: 'spk-selene-2',
    );

    final merged = mergeConversationPreviews(
      [_preview(bundle: _fullBundle)],
      [_preview(bundle: rotated)],
    ).single;

    expect(merged.recipientBundle, same(rotated));
  });

  test('never carries a bundle over to a different peer', () {
    const otherPeer = KeyBundle(
      userId: 'user-lyra',
      deviceId: '',
      handle: 'lyra',
      identityPublicKey: '',
      signedPrekeyBundle: '',
    );

    final merged = mergeConversationPreviews(
      [_preview(bundle: _fullBundle)],
      [_preview(bundle: otherPeer)],
    ).single;

    expect(merged.recipientBundle, same(otherPeer));
  });

  group('a 1:1 with a session stays with the peer it was opened to', () {
    const otherPeer = KeyBundle(
      userId: 'user-lyra',
      deviceId: '',
      handle: 'lyra',
      identityPublicKey: '',
      signedPrekeyBundle: '',
    );

    test('a server preview naming another user updates only the last message and timer', () {
      final local = _preview(bundle: _fullBundle, session: _session(), timer: 30);
      final server = ConversationPreview(
        id: 'conv-1',
        peerHandle: 'lyra',
        peerDisplayName: 'Lyra',
        recipientBundle: otherPeer,
        lastEnvelope: null,
        updatedAt: DateTime.utc(2026, 4, 2),
        sessionState: null,
        disappearingTimerSeconds: 300,
      );

      final merged = mergeConversationPreviews([local], [server]).single;

      expect(merged.peerHandle, 'selene');
      expect(merged.peerDisplayName, 'Selene');
      expect(merged.recipientBundle, same(_fullBundle));
      expect(merged.sessionState, same(local.sessionState));
      expect(merged.updatedAt, DateTime.utc(2026, 4, 2));
      expect(merged.disappearingTimerSeconds, 300);
    });

    test('a server preview turning it into a group is not taken', () {
      final local = _preview(bundle: _fullBundle, session: _session());
      final server = _preview().copyWith(
        type: ConversationType.group,
        members: const [GroupMember(userId: 'user-lyra', handle: 'lyra')],
      );

      final merged = mergeConversationPreviews([local], [server]).single;

      expect(merged.type, ConversationType.direct);
      expect(merged.members, isEmpty);
      expect(merged.recipientBundle, same(_fullBundle));
    });

    test('a new handle for the same user still comes from the server', () {
      final local = _preview(bundle: _fullBundle, session: _session());
      final server = _preview().copyWith(peerHandle: 'selene-renamed');

      final merged = mergeConversationPreviews([local], [server]).single;

      expect(merged.peerHandle, 'selene-renamed');
      expect(merged.recipientBundle, same(_fullBundle));
    });
  });

  group('a bound 1:1 the previous list left out', () {
    const bound = {'conv-1': ConversationPeer(userId: 'user-selene', handle: 'selene')};
    final relabelled = ConversationPreview(
      id: 'conv-1',
      peerHandle: 'lyra',
      peerDisplayName: 'Lyra',
      recipientBundle: const KeyBundle(
        userId: 'user-lyra',
        deviceId: '',
        handle: 'lyra',
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 2),
      disappearingTimerSeconds: 300,
    );

    test('comes back with its bound peer, not the one the server names', () {
      final merged = mergeConversationPreviews(const [], [relabelled], bound: bound).single;

      expect(merged.type, ConversationType.direct);
      expect(merged.peerHandle, 'selene');
      expect(merged.peerDisplayName, isNull);
      expect(merged.recipientBundle.userId, 'user-selene');
      expect(merged.recipientBundle.identityPublicKey, isEmpty);
      expect(merged.sessionState, isNull);
      expect(merged.updatedAt, DateTime.utc(2026, 4, 2));
      expect(merged.disappearingTimerSeconds, 300);
    });

    test('is not turned into a group', () {
      final asGroup = _preview().copyWith(
        type: ConversationType.group,
        members: const [GroupMember(userId: 'user-lyra', handle: 'lyra')],
      );

      final merged = mergeConversationPreviews(const [], [asGroup], bound: bound).single;

      expect(merged.type, ConversationType.direct);
      expect(merged.members, isEmpty);
      expect(merged.recipientBundle.userId, 'user-selene');
    });

    test('listed with its bound peer passes through', () {
      final merged = mergeConversationPreviews(const [], [_preview()], bound: bound).single;

      expect(merged.peerHandle, 'selene');
      expect(merged.peerDisplayName, 'Selene');
    });
  });

  test('new conversations pass through and vanished ones are dropped', () {
    final merged = mergeConversationPreviews(
      [_preview(id: 'conv-gone', bundle: _fullBundle, session: _session())],
      [_preview(id: 'conv-new')],
    );

    expect(merged.map((preview) => preview.id), ['conv-new']);
    expect(merged.single.sessionState, isNull);
  });
}
