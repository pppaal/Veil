import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/keys_api.dart';
import '../conversation_models.dart';
import 'conversation_peer_bindings.dart';
import 'identity_trust.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'peer_bundle_cache.dart';
import 'session_policy.dart';

/// Decides whom a 1:1 conversation's next frame is sealed to: its
/// established session while the identity pins accept it, otherwise the
/// key directory's answer once the pins accept that, bootstrapping a
/// session only when no usable one exists.
class PeerSessionResolver {
  PeerSessionResolver({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required ConversationSessionBootstrapper sessions,
    required KeysApi keys,
    required IdentityTrust trust,
    required ConversationPeerBindings bindings,
  })  : _store = store,
        _session = session,
        _sessions = sessions,
        _keys = keys,
        _trust = trust,
        _bindings = bindings;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final ConversationSessionBootstrapper _sessions;
  final KeysApi _keys;
  final IdentityTrust _trust;
  final ConversationPeerBindings _bindings;
  final PeerBundleCache _peerBundles = PeerBundleCache();
  // Conversations whose next send must ask the directory first: a rekey was
  // armed, or a frame arrived from a peer device the session is not bound to.
  final Set<String> _directoryRecheck = <String>{};

  bool hasSessionFor(String conversationId) => _sessions.hasSessionFor(conversationId);

  /// Makes the next send in each of [conversationIds] ask the directory.
  void recheckDirectory(Iterable<String> conversationIds) => _directoryRecheck.addAll(conversationIds);

  /// Lets [conversationId] keep its session without asking the directory,
  /// which may still serve a key the user declined.
  void skipDirectoryRecheck(String conversationId) => _directoryRecheck.remove(conversationId);

  void clear() {
    _peerBundles.clear();
    _directoryRecheck.clear();
  }

  // Steady-state sends on an established session use the stored bundle and
  // never touch the directory, as long as the pins accept it as they stand
  // now: the user may since have verified another device of the contact,
  // and a conversation that lost what it knew names no identity at all.
  // Anything else asks the directory, whose answer must pass the pins
  // before anything is sealed to it. A pending recheck, and a stored bundle
  // the pins stopped accepting, ask it fresh rather than repeat a cached
  // answer; the recheck is only cleared once that answer has been applied.
  // A session the engine reports [sessionMoved] reaches nobody this
  // conversation chose, so it is replaced.
  //
  // So a pending identity change holds back only what would need it: a
  // steady-state send goes ahead while the pins still accept the identity
  // its session encrypts to, otherwise a single refused frame, which the
  // relay can forge at will, would stop the conversation.
  Future<KeyBundle> bundleForSend(ConversationPreview conversation, {bool sessionMoved = false}) async {
    await _listedPeerNotHeld(conversation);
    var recheck = sessionMoved || _directoryRecheck.contains(conversation.id);
    if (!recheck && _sessions.hasSessionFor(conversation.id)) {
      final bundle = conversation.recipientBundle;
      if (await _trust.trusts(bundle.userId, bundle.deviceId, bundle.identityPublicKey)) return bundle;
      recheck = true;
    }
    final handle = conversation.peerHandle;
    final served = (recheck ? null : _peerBundles.fresh(handle)) ?? await _fetchPeerBundle(handle, KeyClaim.active);
    final bundle = await _applyDirectoryAnswer(conversation.id, served, mustBootstrap: sessionMoved);
    _directoryRecheck.remove(conversation.id);
    return bundle;
  }

  /// Replaces the session of the 1:1 [conversationId] with a fresh X3DH
  /// handshake to the peer's current directory entry, which must pass the
  /// pins first. Returns false when there is no session to replace.
  Future<bool> renewSession(String conversationId) async {
    final conversation = _store.conversationById(conversationId);
    if (conversation == null ||
        conversation.type != ConversationType.direct ||
        !_session.isAuthenticated ||
        !_sessions.hasSessionFor(conversationId)) {
      return false;
    }
    final served = await _fetchPeerBundle(conversation.peerHandle, KeyClaim.active);
    await _applyDirectoryAnswer(conversationId, served, mustBootstrap: true);
    _directoryRecheck.remove(conversationId);
    return true;
  }

  /// The key [handle]'s active device currently publishes, as the directory
  /// serves it. Read-only: it claims no prekey and changes no session or pin.
  Future<KeyBundle> publishedBundle(String handle) async => (await _activeDeviceOf(handle, KeyClaim.none)).bundle;

  // Best effort, once per inbound session whose handshake identity this
  // device did not see (one the engine already held when the conversation
  // first recorded it): gives the responder its peer's identity key for
  // safety numbers and later checks. Never bootstraps, so it cannot replace
  // the session the peer just opened, and claims no prekey it would not use.
  Future<void> learnPeerIdentity(ConversationPreview conversation) async {
    final handle = conversation.peerHandle;
    final served = _peerBundles.fresh(handle) ?? await _fetchPeerBundle(handle, KeyClaim.none);
    await _applyDirectoryAnswer(conversation.id, served, mayBootstrap: false);
  }

  // A conversation listed under a handle this device knows as another
  // account, or under one no honest relay issues, seals to nobody and asks
  // the directory nothing until the user acknowledges the account (see
  // ConversationPeerBindings.holdFor). Returns the peer it is listed with.
  Future<ConversationPeer> _listedPeerNotHeld(ConversationPreview conversation) async {
    final listed = ConversationPeer(userId: conversation.recipientBundle.userId, handle: conversation.peerHandle);
    if (await _bindings.holdFor(conversation.id, listed) case final hold?) {
      throw PeerAccountHeldException(conversation.id, hold);
    }
    return listed;
  }

  Future<DirectoryDevice> _fetchPeerBundle(String handle, KeyClaim claim) async {
    final active = await _activeDeviceOf(handle, claim);
    _peerBundles.remember(handle, active);
    return active;
  }

  Future<DirectoryDevice> _activeDeviceOf(String handle, KeyClaim claim) async {
    final entry = await _keys.lookup(handle, accessToken: _session.current.accessToken, claim: claim);
    return entry.activeDevice ?? (throw StateError('The directory lists no active device for @$handle.'));
  }

  // Fits a direct conversation to a directory answer: a bootstrap only when
  // no usable session exists, otherwise the session is kept (see
  // keepSession). Nothing is adopted or bootstrapped to before the identity
  // pins accept it. Returns the bundle the conversation now holds.
  Future<KeyBundle> _applyDirectoryAnswer(
    String conversationId,
    DirectoryDevice served, {
    bool mayBootstrap = true,
    bool mustBootstrap = false,
  }) async {
    final conversation = _store.conversationById(conversationId);
    final bundle = served.bundle;
    final session = _session.signedIn;
    if (conversation == null || session == null) {
      return bundle;
    }
    final listed = await _listedPeerNotHeld(conversation);
    final peerUserId = listed.userId;
    if (bundle.userId != peerUserId) {
      throw StateError('The directory answered @${conversation.peerHandle} with another user.');
    }
    await _trust.require(conversationId, peerUserId, bundle.deviceId, bundle.identityPublicKey);
    // The first identity the pins admit binds the conversation to the peer
    // it is listed with (see ConversationPeerBindings).
    await _bindings.bindAll({conversationId: listed});
    final action = mustBootstrap
        ? SessionAction.bootstrap
        : decideSession(
            engineHasSession: _sessions.hasSessionFor(conversationId),
            session: conversation.sessionState,
            localDeviceId: session.deviceId,
            bundle: bundle,
          );
    if (action == SessionAction.reuse) {
      _store.updateConversation(conversationId, (preview) => keepSession(preview, bundle));
    } else if (mayBootstrap) {
      final material = await _sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: session.deviceId,
          localUserId: session.userId,
          remoteUserId: bundle.userId,
          remoteDeviceId: bundle.deviceId,
          remoteIdentityPublicKey: bundle.identityPublicKey,
          remoteSignedPrekeyBundle: bundle.signedPrekeyBundle,
          remoteOneTimePrekey: served.oneTimePrekey,
        ),
      );
      _peerBundles.spendOneTimePrekey(conversation.peerHandle);
      final sessionState = sessionStateFromMaterial(material, remoteIdentityPublicKey: bundle.identityPublicKey);
      _store.updateConversation(
        conversationId,
        (preview) => preview.copyWith(recipientBundle: bundle, sessionState: sessionState),
      );
    }
    return _store.conversationById(conversationId)?.recipientBundle ?? bundle;
  }
}
