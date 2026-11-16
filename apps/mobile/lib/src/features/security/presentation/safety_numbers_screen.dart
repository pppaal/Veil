import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/identity/trusted_identity.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../core/util/base64url.dart';
import '../../../core/util/constant_time.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/identity_trust.dart';
import '../domain/safety_numbers.dart';
import 'safety_number_cards.dart';
import 'safety_number_dialogs.dart';
import 'safety_number_view_data.dart';

/// Safety numbers v2 over the identities this device pinned: what it
/// actually encrypts to, never what the directory says right now. The
/// directory is consulted only to warn when it serves a different key or
/// device.
class SafetyNumbersScreen extends ConsumerStatefulWidget {
  const SafetyNumbersScreen({
    required this.conversationId,
    this.memberUserId,
    super.key,
  });

  // What the tests find: the spinner, the failed state, the change-elsewhere notice.
  static const loadingKey = ValueKey('safety-number-loading');
  static const errorKey = ValueKey('safety-number-error');
  static const changeElsewhereKey = ValueKey('safety-number-change-elsewhere');

  final String conversationId;
  // When set and the conversation is a group, renders the safety-number
  // detail for that specific member. When null on a group, renders the
  // member list. Ignored for direct conversations.
  final String? memberUserId;

  @override
  ConsumerState<SafetyNumbersScreen> createState() =>
      _SafetyNumbersScreenState();
}

class _SafetyNumbersScreenState extends ConsumerState<SafetyNumbersScreen> {
  Future<SafetyNumbersViewData>? _loader;
  bool _renewing = false;
  // A scanned code that did not match; the screen stays failed until left.
  bool _scanMismatch = false;
  late final StreamSubscription<PendingIdentityChange> _changes;
  // Whose identity the loaded screen is about: the peer, or a group's members.
  Set<String> _shownUserIds = const {};
  // The changes waiting for review that the loaded screen was drawn from.
  String _shownPending = '';
  // The user's own decision on a change is being carried out.
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _shownPending = _pendingNow();
    _loader = _load();
    // A newer change replaces the one on screen, so its number is no longer
    // the one to compare; a change about someone shown, raised in any other
    // conversation, takes their verified mark away.
    _changes = ref.read(messengerControllerProvider).identityChanges.listen((_) => _reloadIfPendingChanged());
  }

  // The changes waiting for review that this page shows or stands back
  // for: the one its conversation holds, and any about the people shown.
  String _pendingNow() {
    final messenger = ref.read(messengerControllerProvider);
    return [
      messenger.pendingIdentityChangeFor(widget.conversationId),
      for (final userId in _shownUserIds) messenger.pendingIdentityChangeAbout(userId),
    ].map((change) => change == null ? '' : '${change.conversationId} ${change.deviceId} ${change.presentedKey}').join('|');
  }

  // Reads the page again when a change it shows was raised, replaced or
  // settled since it was drawn: wherever that happened, and whether or not
  // the page was left meanwhile.
  void _reloadIfPendingChanged() {
    if (!mounted || _deciding || _pendingNow() == _shownPending) return;
    unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  Future<SafetyNumbersViewData> _load() async {
    final conversation = ref.read(messengerControllerProvider).conversationById(widget.conversationId);
    if (conversation == null) {
      throw StateError('Conversation not found');
    }
    // Right after an upgrade the pins are still being carried over.
    await ref.read(identityTrustProvider).ready;
    if (conversation.type == ConversationType.group && widget.memberUserId == null) {
      return _loadGroupList(conversation);
    }
    return _loadDetail(conversation);
  }

  Future<SafetyGroupListData> _loadGroupList(ConversationPreview conversation) async {
    final messenger = ref.read(messengerControllerProvider);
    final session = ref.read(appSessionProvider);
    // You can't verify your own identity number against yourself.
    final members = conversation.members.where((m) => m.userId != session.userId).toList(growable: false);
    _shownUserIds = {for (final member in members) member.userId};
    _shownPending = _pendingNow();
    // Verified only when every device of theirs is, and no identity change
    // of theirs waits for review, here or in any other conversation: any
    // pinned device of a member may hold this group's chain keys, not just
    // the one compared.
    final pendingUserId = messenger.pendingIdentityChangeFor(conversation.id)?.userId;
    final verified = <String>{
      for (final member in members)
        if (member.userId != pendingUserId && await messenger.isUserVerified(member.userId)) member.userId,
    };
    return SafetyGroupListData(groupName: conversation.groupMeta?.name, members: members, verifiedUserIds: verified);
  }

  Future<SafetyDetailData> _loadDetail(ConversationPreview conversation) async {
    final messenger = ref.read(messengerControllerProvider);
    final resolver = ref.read(identityTrustProvider).resolver;
    final localUserId = ref.read(appSessionProvider).userId;
    final isDirect = conversation.type == ConversationType.direct;
    final GroupMember peer = isDirect
        ? GroupMember(
            userId: conversation.recipientBundle.userId,
            handle: conversation.peerHandle,
            displayName: conversation.peerDisplayName,
          )
        : conversation.members.firstWhere(
            (m) => m.userId == widget.memberUserId,
            orElse: () => throw StateError('Member not in this group'),
          );
    _shownUserIds = {peer.userId};
    _shownPending = _pendingNow();

    final identityRef = await ref.read(secureStorageProvider).readIdentityPrivateRef();
    if (identityRef == null || identityRef.isEmpty || localUserId == null) {
      throw StateError('Local identity is unavailable');
    }
    final localKey = base64UrlNoPadDecode(
      await ref.read(cryptoAdapterProvider).identity.extractIdentityPublicKeyFromPrivateRef(identityRef),
    );

    final served = await _directoryKeyOf(peer.handle);
    final pins = await resolver.pinsForUser(peer.userId);
    final pin = _pinToShow(
      pins,
      isDirect
          ? [conversation.sessionState?.remoteDeviceId, conversation.recipientBundle.deviceId, served?.deviceId]
          : [served?.deviceId],
    );
    final pending = messenger.pendingIdentityChangeFor(conversation.id);
    final change = pending != null && pending.userId == peer.userId ? pending : null;
    // A change of theirs that another conversation holds: reviewed there,
    // and until then nothing here may call them verified.
    final elsewhere = change == null ? messenger.pendingIdentityChangeAbout(peer.userId) : null;

    Future<String?> numberFor(String? key) async =>
        key == null ? null : _safetyNumberOffThread(localUserId, localKey, peer.userId, base64UrlNoPadDecode(key));

    return SafetyDetailData(
      peer: peer,
      localUserId: localUserId,
      localKey: localKey,
      pin: pin,
      number: await numberFor(pin?.identityKey),
      pendingChange: change,
      pendingNumber: await numberFor(change?.presentedKey),
      changeElsewhere: elsewhere,
      mayDecline: change != null && messenger.mayDeclineIdentityChange(conversation.id),
      directory: served == null || pin == null
          ? null
          : served.deviceId != pin.deviceId
              ? SafetyDirectoryAnswer.otherDevice
              : constantTimeBytesEqual(base64UrlNoPadDecode(served.key), base64UrlNoPadDecode(pin.identityKey))
                  ? SafetyDirectoryAnswer.matches
                  : SafetyDirectoryAnswer.otherKey,
      isDirect: isDirect,
    );
  }

  // Offline or unknown to the directory: the screen still shows the pins.
  Future<({String deviceId, String key})?> _directoryKeyOf(String handle) async {
    try {
      final bundle = await ref.read(messengerControllerProvider).fetchPeerKeyBundle(handle);
      return (deviceId: bundle.deviceId, key: bundle.identityPublicKey);
    } catch (_) {
      return null;
    }
  }

  // The pin of the first device in [preferred] that has one. A direct
  // conversation prefers the device its session is bound to, because that
  // is what every reply is encrypted to, whatever the directory serves now;
  // a group seals to each of a member's devices, and the one the directory
  // calls active stands for them.
  static TrustedIdentity? _pinToShow(List<TrustedIdentity> pins, List<String?> preferred) {
    for (final deviceId in preferred) {
      final match = pins.where((pin) => pin.deviceId == deviceId).firstOrNull;
      if (match != null) return match;
    }
    return pins.lastOrNull;
  }

  Future<void> _reload() async {
    // Taken before the read starts, so that what settles while it runs is
    // not asked for twice.
    _shownPending = _pendingNow();
    setState(() {
      _loader = _load();
    });
    try {
      await _loader;
    } catch (_) {
      // The page shows that it could not be read, and offers to retry.
    }
  }

  // Opens another safety-number screen on top of this one; what was decided
  // there (a member verified, a change settled) shows here on the way back.
  Future<void> _openAndReload(String location) async {
    await context.push(location);
    if (mounted) await _reload();
  }

  static String _memberLocation(String conversationId, String userId) =>
      '/safety-numbers/$conversationId?member=${Uri.encodeQueryComponent(userId)}';

  // Where [change] is reviewed: the 1:1 that holds it, or its member's page
  // in the group that does.
  String _changeLocation(PendingIdentityChange change) {
    final holder = ref.read(messengerControllerProvider).conversationById(change.conversationId);
    return holder?.type == ConversationType.group
        ? _memberLocation(change.conversationId, change.userId)
        : '/safety-numbers/${change.conversationId}';
  }

  Future<void> _markVerified(SafetyDetailData data) async {
    VeilHaptics.medium();
    final pin = data.pin!;
    await ref.read(identityTrustProvider).markVerified(pin.userId, pin.deviceId, pin.identityKey);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    showVeilToast(context, AppLocalizations.of(context).safetyNumbersMarkedVerified);
  }

  // Approves exactly [change], the identity the user reviewed: if a newer
  // one replaced it meanwhile, nothing is accepted and the screen shows the
  // newer one instead.
  Future<void> _acceptChange(PendingIdentityChange change, {required bool reverified}) => _decide(
        () => ref
            .read(messengerControllerProvider)
            .approveIdentityChange(widget.conversationId, reverified: reverified, reviewed: change),
      );

  // Keeps the pinned identity in place of exactly [change]; a newer change
  // that replaced it meanwhile stays pending and is shown instead.
  Future<void> _declineChange(PendingIdentityChange change) => _decide(
        () => ref.read(messengerControllerProvider).declineIdentityChange(widget.conversationId, reviewed: change),
      );

  // Runs the user's decision on a change and then reads the page once, when
  // the decision is through: what the messenger reports on the way is not
  // read half-done.
  Future<void> _decide(Future<void> Function() decision) async {
    VeilHaptics.medium();
    _deciding = true;
    try {
      await decision();
    } on StateError {
      if (mounted) {
        showVeilToast(
          context,
          AppLocalizations.of(context).safetyNumbersChangeReplaced,
          tone: VeilTone.warn,
        );
      }
    } finally {
      _deciding = false;
    }
    if (!mounted) return;
    await _reload();
  }

  // The tap that opens this is not the approval: the user must affirm, next
  // to the new number, that they compared it out of band.
  Future<void> _confirmReverification(SafetyDetailData data) async {
    final compared = await showDialog<bool>(
      context: context,
      builder: (context) => SafetyReverifyDialog(peer: data.peer.title, number: data.pendingNumber!),
    );
    if (compared != true || !mounted) return;
    await _acceptChange(data.pendingChange!, reverified: true);
  }

  // The code the contact pastes on their phone to compare both identities in
  // one step: what the QR code held, as text, since no app here scans one.
  Future<void> _copyMyCode(SafetyDetailData data, String remoteKey) async {
    final copied = AppLocalizations.of(context).safetyNumbersCodeCopied;
    await Clipboard.setData(ClipboardData(text: _qrPayload(data, remoteKey)));
    if (!mounted) return;
    showVeilToast(context, copied);
  }

  Future<void> _compareScannedCode(SafetyDetailData data) async {
    final l10n = AppLocalizations.of(context);
    final scanned = await showDialog<String>(context: context, builder: (context) => const SafetyScannedCodeDialog());
    if (scanned == null || scanned.trim().isEmpty || !mounted) return;
    final change = data.pendingChange;
    final remoteKey = change?.presentedKey ?? data.pin!.identityKey;
    final outcome = verifyScannedSafetyQr(
      scannedPayload: scanned.trim(),
      localUserId: data.localUserId,
      localIdentityKey: data.localKey,
      remoteUserId: data.peer.userId,
      remoteIdentityKey: base64UrlNoPadDecode(remoteKey),
    );
    switch (outcome) {
      case SafetyQrVerification.verified:
        if (change != null) {
          await _acceptChange(change, reverified: true);
        } else {
          await _markVerified(data);
        }
      case SafetyQrVerification.mismatch:
        VeilHaptics.medium();
        setState(() => _scanMismatch = true);
      case SafetyQrVerification.unsupportedVersion:
        showVeilToast(context, l10n.safetyNumbersScanUnsupported, tone: VeilTone.warn);
      case SafetyQrVerification.malformed:
        showVeilToast(context, l10n.safetyNumbersScanInvalid, tone: VeilTone.warn);
    }
  }

  Future<void> _renewSession() async {
    if (_renewing) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => const SafetyRenewSessionDialog());
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _renewing = true);
    VeilHaptics.medium();
    try {
      final messenger = ref.read(messengerControllerProvider);
      final renewed = await messenger.renewSession(widget.conversationId);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showVeilToast(
        context,
        renewed ? l10n.safetyNumbersSessionRotated : l10n.safetyNumbersNoSessionYet,
      );
    } catch (_) {
      // Why it failed is the relay's or the engine's own wording; the user
      // is told that it did, in their language.
      if (!mounted) return;
      showVeilToast(
        context,
        AppLocalizations.of(context).safetyNumbersRotationFailed,
        tone: VeilTone.warn,
      );
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Only the messenger, not its stream, says when a change is settled: an open page then reads again.
    ref.listen(messengerControllerProvider, (_, __) => _reloadIfPendingChanged());
    return VeilShell(
      title: l10n.safetyNumbersTitle,
      child: FutureBuilder<SafetyNumbersViewData>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted);
            return Center(
              key: SafetyNumbersScreen.loadingKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: VeilSpace.sm),
                Text(l10n.safetyNumbersLoadingTitle, style: muted),
              ]),
            );
          }
          if (snapshot.hasError) {
            return _buildErrorBody(context);
          }
          final data = snapshot.data!;
          if (data is SafetyGroupListData) {
            return _buildGroupList(context, data);
          }
          return _buildDetail(context, data as SafetyDetailData);
        },
      ),
    );
  }

  // The error itself is for a log, not for the user: it names internals.
  Widget _buildErrorBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilEmptyState(
      key: SafetyNumbersScreen.errorKey,
      title: l10n.safetyNumbersErrorTitle,
      action: VeilButton(
        label: l10n.safetyNumbersRetry,
        tone: VeilButtonTone.secondary,
        expanded: false,
        onPressed: _reload,
      ),
    );
  }

  // A row per member; only the verified ones are labelled, as Signal labels
  // only the positive state in a list. No footer.
  Widget _buildGroupList(BuildContext context, SafetyGroupListData data) {
    final l10n = AppLocalizations.of(context);
    if (data.members.isEmpty) {
      return VeilEmptyState(title: l10n.safetyNumbersNoMembersTitle);
    }
    return ListView(
      children: [
        VeilGroup(
          inset: 68,
          children: [
            for (final member in data.members)
              VeilRow(
                leading: VeilAvatar(name: member.title, seed: member.handle),
                title: member.title,
                subtitle: '@${member.handle}',
                trailing: data.verifiedUserIds.contains(member.userId) ? const SafetyVerifiedMark(chevron: true) : null,
                onTap: () => _openAndReload(_memberLocation(widget.conversationId, member.userId)),
              ),
          ],
        ),
      ],
    );
  }

  // Content first, as Signal's: a change of the peer's identity is announced
  // before anything else; then who the number is about and whether they are
  // verified, the number with one sentence on comparing it, the one action
  // on it, and the codes to copy and paste as two quiet buttons.
  Widget _buildDetail(BuildContext context, SafetyDetailData data) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final pin = data.pin;
    final change = data.pendingChange;
    // Reviewed in the conversation that holds it; here it only says so.
    final elsewhere = data.changeElsewhere;
    final settled = change == null && elsewhere == null;
    // "Verified" is about the pinned key, which is what this device
    // encrypts to. A change of theirs that waits for review puts it in
    // question (the pin itself stays verified meanwhile), and so does a scan
    // that just failed, for as long as the page stays open. A directory that
    // serves another key does not: nothing is sent to that key before it is
    // reviewed, and its notice says so under the mark.
    final verified = settled && !_scanMismatch && (pin?.isVerified ?? false);
    const gap = SizedBox(height: VeilSpace.md);
    const section = SizedBox(height: VeilSpace.xl);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);
    final howTo = Text(l10n.safetyNumbersDetailBody(data.peer.title), style: muted);
    // The code to copy goes with the number on screen: the new one while a
    // change waits.
    Widget codes(String remoteKey) => SafetyCodeButtons(
          onCopy: () => _copyMyCode(data, remoteKey),
          onPaste: _scanMismatch ? null : () => _compareScannedCode(data),
        );

    return ListView(
      padding: VeilShell.formPadding,
      children: [
        if (change != null) ...[
          _keyChangedNotice(l10n, data),
          gap,
        ] else if (elsewhere != null) ...[
          // The way to where the change is reviewed, in place of what would
          // confirm the pinned key (its code, "mark as verified", a scan).
          VeilNotice(
            key: SafetyNumbersScreen.changeElsewhereKey,
            tone: VeilTone.warn,
            margin: EdgeInsets.zero,
            title: l10n.safetyNumbersChangedElsewhereTitle,
            message: l10n.safetyNumbersChangedElsewhereBody,
            actionLabel: l10n.safetyNumbersReviewChange,
            onAction: () => _openAndReload(_changeLocation(elsewhere)),
          ),
          gap,
        ],
        SafetyPeerHeader(name: data.peer.title, handle: data.peer.handle, verified: verified),
        if (_scanMismatch) ...[
          gap,
          VeilNotice(
            tone: VeilTone.warn,
            margin: EdgeInsets.zero,
            title: l10n.safetyNumbersScanMismatchTitle,
            message: l10n.safetyNumbersScanMismatchBody,
          ),
        ],
        if (data.directory == SafetyDirectoryAnswer.otherKey) ...[
          gap,
          VeilNotice(
            tone: VeilTone.warn,
            margin: EdgeInsets.zero,
            title: l10n.safetyNumbersDirectoryMismatchTitle,
            message: l10n.safetyNumbersDirectoryMismatchBody,
          ),
        ],
        if (data.directory == SafetyDirectoryAnswer.otherDevice) ...[
          gap,
          VeilNotice(
            tone: VeilTone.warn,
            margin: EdgeInsets.zero,
            title: l10n.safetyNumbersDirectoryOtherDeviceTitle,
            message: l10n.safetyNumbersDirectoryOtherDeviceBody,
          ),
        ],
        if (pin == null) ...[
          section,
          Text(l10n.safetyNumbersNoPinTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: VeilSpace.xxs),
          Text(l10n.safetyNumbersNoPinBody, style: muted),
        ],
        if (change != null) ...[
          section,
          ..._pendingChangeSection(context, data, change, codes: codes(change.presentedKey), howTo: howTo),
        ] else if (elsewhere != null) ...[
          if (pin != null) ...[
            section,
            SafetyNumberCard(groups: formatSafetyNumber(data.number!), header: l10n.safetyNumbersCurrentNumberHeader),
          ],
        ] else if (pin != null) ...[
          section,
          SafetyNumberCard(groups: formatSafetyNumber(data.number!)),
          const SizedBox(height: VeilSpace.sm),
          // How to compare, under the number it is about and above the
          // button that says it was done.
          howTo,
          if (verified) ...[
            const SizedBox(height: VeilSpace.xs),
            Text(l10n.safetyNumbersVerifiedOn(_formatDate(pin.verifiedAt!, l10n)), style: muted),
          ],
          section,
          if (!verified) ...[
            VeilButton(
              label: l10n.safetyNumbersMarkVerified,
              onPressed: _scanMismatch ? null : () => _markVerified(data),
            ),
            const SizedBox(height: VeilSpace.xs),
          ],
          codes(pin.identityKey),
        ],
        if (data.isDirect) ...[
          section,
          VeilButton(
            label: _renewing ? l10n.safetyNumbersRotating : l10n.safetyNumbersRotateButton,
            tone: VeilButtonTone.ghost,
            onPressed: _renewing ? null : _renewSession,
          ),
        ],
      ],
    );
  }

  // The identity this conversation is held back on: its number, which the
  // user compares before accepting it, and the decision right under it. A
  // verified contact is accepted only through a matching scanned code or an
  // explicit affirmation that the new number was compared, never with a
  // single tap. The pinned number follows for reference.
  List<Widget> _pendingChangeSection(
    BuildContext context,
    SafetyDetailData data,
    PendingIdentityChange change, {
    required Widget codes,
    required Widget howTo,
  }) {
    final l10n = AppLocalizations.of(context);
    return [
      SafetyNumberCard(groups: formatSafetyNumber(data.pendingNumber!), header: l10n.safetyNumbersNewNumberHeader),
      const SizedBox(height: VeilSpace.sm),
      // How to compare is said for the new number too: it is the one the
      // decision under it is about.
      howTo,
      const SizedBox(height: VeilSpace.xl),
      if (change.requiresReverification)
        VeilButton(
          label: l10n.safetyNumbersReVerify,
          onPressed: _scanMismatch ? null : () => _confirmReverification(data),
        )
      else
        VeilButton(
          label: l10n.safetyNumbersAcceptNewKey,
          onPressed: _scanMismatch ? null : () => _acceptChange(change, reverified: false),
        ),
      // Accepting is never the only way out of a change the relay may have
      // forged: the user can keep what was pinned. Not when the change is
      // about the identity the session already sends to, though: there is
      // no current key to keep in its place.
      if (data.mayDecline) ...[
        const SizedBox(height: VeilSpace.xs),
        VeilButton(
          label: l10n.safetyNumbersKeepCurrentKey,
          tone: VeilButtonTone.secondary,
          onPressed: () => _declineChange(change),
        ),
      ],
      const SizedBox(height: VeilSpace.xs),
      // The peer compares against the new key, so the code to copy is the
      // one that goes with the new number.
      codes,
    ];
  }

  // That the peer's identity changed, and since when it differs from the
  // one the user verified. The decision is the buttons under the number.
  Widget _keyChangedNotice(AppLocalizations l10n, SafetyDetailData data) {
    final verifiedAt = data.pin?.verifiedAt;
    return VeilNotice(
      tone: VeilTone.warn,
      margin: EdgeInsets.zero,
      title: l10n.safetyNumbersKeyChangedTitle,
      message: verifiedAt != null
          ? l10n.safetyNumbersKeyChangedMessage(_formatDate(verifiedAt, l10n))
          : l10n.safetyNumbersPendingBody,
    );
  }

  static String _qrPayload(SafetyDetailData data, String remoteKey) => encodeSafetyQrPayload(
        localUserId: data.localUserId,
        localIdentityKey: data.localKey,
        remoteUserId: data.peer.userId,
        remoteIdentityKey: base64UrlNoPadDecode(remoteKey),
      );
}

// About 10k SHA-512 rounds, so off the UI isolate. Top level, so the
// closure sent to the isolate holds nothing but these arguments.
Future<String> _safetyNumberOffThread(String localUserId, List<int> localKey, String remoteUserId, List<int> remoteKey) =>
    Isolate.run(() => computeSafetyNumberV2(
          localUserId: localUserId,
          localIdentityKey: localKey,
          remoteUserId: remoteUserId,
          remoteIdentityKey: remoteKey,
        ));

String _formatDate(DateTime value, AppLocalizations l10n) =>
    DateFormat.yMMMd(l10n.localeName).format(value.toLocal());
