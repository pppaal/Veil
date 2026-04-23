import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_state.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../domain/safety_numbers.dart';

class SafetyNumbersScreen extends ConsumerStatefulWidget {
  const SafetyNumbersScreen({
    required this.conversationId,
    this.memberUserId,
    super.key,
  });

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
  Future<_SafetyNumbersViewData>? _loader;
  bool _rekeying = false;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<_SafetyNumbersViewData> _load() async {
    final messenger = ref.read(messengerControllerProvider);
    final ConversationPreview? conversation = messenger.conversations
        .cast<ConversationPreview?>()
        .firstWhere(
          (c) => c?.id == widget.conversationId,
          orElse: () => null,
        );
    if (conversation == null) {
      throw StateError('Conversation not found');
    }

    final isGroup = conversation.type == ConversationType.group;
    if (isGroup && widget.memberUserId == null) {
      return _loadGroupList(conversation);
    }
    return _loadDetail(conversation);
  }

  Future<_GroupListData> _loadGroupList(ConversationPreview conversation) async {
    final storage = ref.read(secureStorageProvider);
    final session = ref.read(appSessionProvider);
    final verifications =
        await storage.readSafetyVerificationsForGroup(widget.conversationId);
    // Hide self from the list — you can't verify your own identity number
    // against yourself.
    final members = conversation.members
        .where((m) => m.userId != session.userId)
        .toList(growable: false);
    return _GroupListData(
      groupName: conversation.groupMeta?.name,
      members: members,
      verifications: verifications,
    );
  }

  Future<_DetailData> _loadDetail(ConversationPreview conversation) async {
    final messenger = ref.read(messengerControllerProvider);
    final storage = ref.read(secureStorageProvider);

    String peerHandle;
    String? peerDisplayName;
    String peerPubB64;
    String? memberUserId;

    if (conversation.type == ConversationType.group) {
      memberUserId = widget.memberUserId!;
      final member = conversation.members.firstWhere(
        (m) => m.userId == memberUserId,
        orElse: () => throw StateError('Member not in this group'),
      );
      peerHandle = member.handle;
      peerDisplayName = member.displayName;
      // Resolve the member's identity key on demand — group previews don't
      // carry per-member key material.
      final bundle = await messenger.fetchPeerKeyBundle(member.handle);
      peerPubB64 = bundle.identityPublicKey;
    } else {
      peerHandle = conversation.peerHandle;
      peerDisplayName = conversation.peerDisplayName;
      peerPubB64 = conversation.recipientBundle.identityPublicKey;
    }

    if (peerPubB64.isEmpty) {
      throw StateError('Peer identity key is unavailable');
    }

    final identityPrivateRef = await storage.readIdentityPrivateRef();
    if (identityPrivateRef == null || identityPrivateRef.isEmpty) {
      throw StateError('Local identity is unavailable');
    }
    final adapter = ref.read(cryptoAdapterProvider);
    final localPubB64 =
        await adapter.identity.extractIdentityPublicKeyFromPrivateRef(
      identityPrivateRef,
    );

    final number = await computeSafetyNumber(
      localIdentityPublicKey: decodeIdentityPublicKeyB64(localPubB64),
      peerIdentityPublicKey: decodeIdentityPublicKeyB64(peerPubB64),
    );

    final record = await storage.readSafetyVerification(
      widget.conversationId,
      memberUserId: memberUserId,
    );

    return _DetailData(
      peerHandle: peerHandle,
      peerDisplayName: peerDisplayName,
      peerIdentityPublicKey: peerPubB64,
      localIdentityPublicKey: localPubB64,
      number: number,
      verification: record,
      memberUserId: memberUserId,
      isDirect: conversation.type == ConversationType.direct,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loader = _load();
    });
    await _loader;
  }

  Future<void> _markVerified(_DetailData data) async {
    VeilHaptics.medium();
    final storage = ref.read(secureStorageProvider);
    await storage.writeSafetyVerification(
      widget.conversationId,
      SafetyVerificationRecord(
        peerIdentityPublicKey: data.peerIdentityPublicKey,
        safetyNumber: data.number.digits,
        verifiedAt: DateTime.now().toUtc(),
      ),
      memberUserId: data.memberUserId,
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    VeilToast.show(context, message: 'Marked as verified');
  }

  Future<void> _clearVerification(_DetailData data) async {
    VeilHaptics.selection();
    final storage = ref.read(secureStorageProvider);
    await storage.clearSafetyVerification(
      widget.conversationId,
      memberUserId: data.memberUserId,
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    VeilToast.show(context, message: 'Verification cleared');
  }

  Future<void> _rotateSessionKeys() async {
    if (_rekeying) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rotate session keys?'),
        content: const Text(
          'This forces a fresh Diffie-Hellman ratchet step on your next message. '
          'Old skipped message keys for this chat are dropped immediately. '
          'Use this if you suspect this device or your peer\'s device was '
          'briefly exposed — past messages stay readable, but any stolen '
          'session state stops being useful.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _rekeying = true);
    VeilHaptics.medium();
    try {
      final messenger = ref.read(messengerControllerProvider);
      final armed = await messenger.rekeyConversation(widget.conversationId);
      if (!mounted) return;
      VeilToast.show(
        context,
        message: armed
            ? 'Session keys rotated'
            : 'No session yet — send a message first',
      );
    } catch (error) {
      if (!mounted) return;
      VeilToast.show(context, message: 'Rotation failed: $error');
    } finally {
      if (mounted) {
        setState(() => _rekeying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VeilShell(
      title: 'Safety Number',
      child: FutureBuilder<_SafetyNumbersViewData>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(VeilSpace.lg),
              child: VeilLoadingBlock(
                title: 'Deriving safety number',
                body: 'Hashing identity keys locally.',
              ),
            );
          }
          if (snapshot.hasError) {
            return _buildErrorBody(context, snapshot.error!);
          }
          final data = snapshot.data!;
          if (data is _GroupListData) {
            return _buildGroupList(context, data);
          }
          return _buildDetail(context, data as _DetailData);
        },
      ),
    );
  }

  Widget _buildErrorBody(BuildContext context, Object error) {
    return Padding(
      padding: const EdgeInsets.all(VeilSpace.lg),
      child: VeilErrorState(
        title: 'Could not load safety number',
        body: error.toString(),
        action: VeilButton(
          label: 'Retry',
          tone: VeilButtonTone.secondary,
          onPressed: _reload,
        ),
      ),
    );
  }

  Widget _buildGroupList(BuildContext context, _GroupListData data) {
    final palette = VeilPalette.dark;
    if (data.members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(VeilSpace.lg),
        child: VeilErrorState(
          title: 'No other members',
          body:
              'This group has no other participants yet — invite someone to verify.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VeilSpace.md,
        VeilSpace.sm,
        VeilSpace.md,
        VeilSpace.xl,
      ),
      children: [
        VeilHeroPanel(
          eyebrow: 'VERIFY GROUP MEMBERS',
          title: data.groupName == null
              ? 'Verify each member of this group'
              : 'Verify each member of ${data.groupName}',
          body:
              'Tap a member to see their 60-digit safety number. Compare it on '
              'a channel you trust — read it aloud over a call or scan the QR. '
              'A mismatch means that specific member\'s device may be compromised.',
        ),
        const SizedBox(height: VeilSpace.md),
        for (final member in data.members)
          Padding(
            padding: const EdgeInsets.only(bottom: VeilSpace.xs),
            child: VeilListTileCard(
              title: member.title,
              subtitle: '@${member.handle}',
              trailing: _verificationPill(member, data.verifications),
              onTap: () {
                context.push(
                  '/safety-numbers/${widget.conversationId}'
                  '?member=${Uri.encodeQueryComponent(member.userId)}',
                );
              },
            ),
          ),
        const SizedBox(height: VeilSpace.md),
        VeilSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ROTATE GROUP SESSION KEYS',
                style: TextStyle(
                  color: palette.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: VeilSpace.xs),
              Text(
                'Forces a fresh DH ratchet step on the next group message and '
                'drops stashed skipped keys for this group. Affects every '
                'member — use if any participant\'s device was briefly exposed.',
                style: TextStyle(color: palette.textSubtle, fontSize: 13),
              ),
              const SizedBox(height: VeilSpace.md),
              VeilButton(
                label: _rekeying ? 'Rotating…' : 'Rotate group session keys',
                tone: VeilButtonTone.secondary,
                onPressed: _rekeying ? null : _rotateSessionKeys,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _verificationPill(
    GroupMember member,
    Map<String, SafetyVerificationRecord> verifications,
  ) {
    final record = verifications[member.userId];
    if (record == null) {
      return const VeilStatusPill(
        label: 'Unverified',
        tone: VeilBannerTone.info,
      );
    }
    return const VeilStatusPill(
      label: 'Verified',
      tone: VeilBannerTone.good,
    );
  }

  Widget _buildDetail(BuildContext context, _DetailData data) {
    final palette = VeilPalette.dark;
    final verified = data.verification != null &&
        data.verification!.peerIdentityPublicKey == data.peerIdentityPublicKey;
    final keyChanged = data.verification != null && !verified;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VeilSpace.md,
        VeilSpace.sm,
        VeilSpace.md,
        VeilSpace.xl,
      ),
      children: [
        VeilHeroPanel(
          eyebrow: 'VERIFY IDENTITY',
          title: 'Make sure you\'re talking to ${data.peerDisplay}',
          body:
              'Both of you should see the same 60-digit number. Compare on a channel you trust — read it aloud over a call, or scan the QR. If the numbers don\'t match, someone is in the middle of your conversation.',
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: verified ? 'Verified' : 'Unverified',
                tone: verified
                    ? VeilBannerTone.good
                    : keyChanged
                        ? VeilBannerTone.warn
                        : VeilBannerTone.info,
              ),
              VeilStatusPill(
                label: '@${data.peerHandle}',
                tone: VeilBannerTone.info,
              ),
            ],
          ),
        ),
        if (keyChanged) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            tone: VeilBannerTone.warn,
            title: 'Peer identity key changed',
            message:
                'The identity key for this peer is different from the one you verified on ${_formatDate(data.verification!.verifiedAt)}. This can happen after a reinstall — or if someone is impersonating them. Verify again before trusting.',
          ),
        ],
        const SizedBox(height: VeilSpace.md),
        _SafetyNumberCard(groups: data.number.groups),
        const SizedBox(height: VeilSpace.md),
        _QrCard(content: data.number.digits, palette: palette),
        const SizedBox(height: VeilSpace.md),
        if (verified)
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verified on ${_formatDate(data.verification!.verifiedAt)}',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: VeilSpace.xs),
                Text(
                  'If this peer reinstalls or switches devices, this verification is invalidated and you\'ll see a warning.',
                  style: TextStyle(color: palette.textSubtle, fontSize: 13),
                ),
                const SizedBox(height: VeilSpace.md),
                VeilButton(
                  label: 'Clear verification',
                  tone: VeilButtonTone.ghost,
                  onPressed: () => _clearVerification(data),
                ),
              ],
            ),
          )
        else
          VeilButton(
            label: keyChanged ? 'Re-verify with new key' : 'Mark as verified',
            onPressed: () => _markVerified(data),
          ),
        if (data.isDirect) ...[
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ROTATE SESSION KEYS',
                  style: TextStyle(
                    color: palette.textSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: VeilSpace.xs),
                Text(
                  'Forces a fresh DH ratchet step on your next message and '
                  'drops any stashed skipped keys. Use if this device or '
                  'your peer\'s was briefly exposed.',
                  style: TextStyle(color: palette.textSubtle, fontSize: 13),
                ),
                const SizedBox(height: VeilSpace.md),
                VeilButton(
                  label: _rekeying ? 'Rotating…' : 'Rotate session keys',
                  tone: VeilButtonTone.secondary,
                  onPressed: _rekeying ? null : _rotateSessionKeys,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SafetyNumberCard extends StatelessWidget {
  const _SafetyNumberCard({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    final palette = VeilPalette.dark;
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAFETY NUMBER',
            style: TextStyle(
              color: palette.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final g in groups)
                Text(
                  g,
                  style: TextStyle(
                    color: palette.text,
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.content, required this.palette});

  final String content;
  final VeilPalette palette;

  @override
  Widget build(BuildContext context) {
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SCAN TO COMPARE',
              style: TextStyle(
                color: palette.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Container(
            padding: const EdgeInsets.all(VeilSpace.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(VeilRadius.md),
            ),
            child: QrImageView(
              data: content,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(
            'This QR encodes only the 60-digit safety number, not your keys.',
            style: TextStyle(color: palette.textSubtle, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

abstract class _SafetyNumbersViewData {
  const _SafetyNumbersViewData();
}

class _DetailData extends _SafetyNumbersViewData {
  const _DetailData({
    required this.peerHandle,
    required this.peerDisplayName,
    required this.peerIdentityPublicKey,
    required this.localIdentityPublicKey,
    required this.number,
    required this.verification,
    required this.memberUserId,
    required this.isDirect,
  });

  final String peerHandle;
  final String? peerDisplayName;
  final String peerIdentityPublicKey;
  final String localIdentityPublicKey;
  final SafetyNumberResult number;
  final SafetyVerificationRecord? verification;
  // null for direct conversations, set for a specific group member.
  final String? memberUserId;
  final bool isDirect;

  String get peerDisplay =>
      (peerDisplayName != null && peerDisplayName!.isNotEmpty)
          ? peerDisplayName!
          : '@$peerHandle';
}

class _GroupListData extends _SafetyNumbersViewData {
  const _GroupListData({
    required this.groupName,
    required this.members,
    required this.verifications,
  });

  final String? groupName;
  final List<GroupMember> members;
  final Map<String, SafetyVerificationRecord> verifications;
}

String _formatDate(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}
