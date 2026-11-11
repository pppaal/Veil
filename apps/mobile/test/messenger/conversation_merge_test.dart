import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_merge.dart';

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
  bool identityMismatchPending = false,
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
    identityMismatchPending: identityMismatchPending,
  );
}

void main() {
  test('keeps the local session, bundle and identity flag when the server has none', () {
    final local = _preview(
      bundle: _fullBundle,
      session: _session(),
      identityMismatchPending: true,
    );

    final merged = mergeConversationPreviews([local], [_preview()]).single;

    expect(merged.sessionState, same(local.sessionState));
    expect(merged.recipientBundle, same(_fullBundle));
    expect(merged.identityMismatchPending, isTrue);
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

  test('new conversations pass through and vanished ones are dropped', () {
    final merged = mergeConversationPreviews(
      [_preview(id: 'conv-gone', bundle: _fullBundle, session: _session())],
      [_preview(id: 'conv-new')],
    );

    expect(merged.map((preview) => preview.id), ['conv-new']);
    expect(merged.single.sessionState, isNull);
  });
}
