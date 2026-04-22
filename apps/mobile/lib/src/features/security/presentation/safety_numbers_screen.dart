import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  const SafetyNumbersScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<SafetyNumbersScreen> createState() =>
      _SafetyNumbersScreenState();
}

class _SafetyNumbersScreenState extends ConsumerState<SafetyNumbersScreen> {
  Future<_SafetyNumbersData>? _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<_SafetyNumbersData> _load() async {
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
    if (conversation.type != ConversationType.direct) {
      throw const _UnsupportedGroupException();
    }
    final peerPubB64 = conversation.recipientBundle.identityPublicKey;
    if (peerPubB64.isEmpty) {
      throw StateError('Peer identity key is unavailable');
    }

    final storage = ref.read(secureStorageProvider);
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

    final record = await storage.readSafetyVerification(widget.conversationId);
    return _SafetyNumbersData(
      peerHandle: conversation.peerHandle,
      peerDisplayName: conversation.peerDisplayName,
      peerIdentityPublicKey: peerPubB64,
      localIdentityPublicKey: localPubB64,
      number: number,
      verification: record,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loader = _load();
    });
    await _loader;
  }

  Future<void> _markVerified(_SafetyNumbersData data) async {
    VeilHaptics.medium();
    final storage = ref.read(secureStorageProvider);
    await storage.writeSafetyVerification(
      widget.conversationId,
      SafetyVerificationRecord(
        peerIdentityPublicKey: data.peerIdentityPublicKey,
        safetyNumber: data.number.digits,
        verifiedAt: DateTime.now().toUtc(),
      ),
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    VeilToast.show(context, message: 'Marked as verified');
  }

  Future<void> _clearVerification() async {
    VeilHaptics.selection();
    final storage = ref.read(secureStorageProvider);
    await storage.clearSafetyVerification(widget.conversationId);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    VeilToast.show(context, message: 'Verification cleared');
  }

  @override
  Widget build(BuildContext context) {
    return VeilShell(
      title: 'Safety Number',
      child: FutureBuilder<_SafetyNumbersData>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(VeilSpace.lg),
              child: VeilLoadingBlock(
                title: 'Deriving safety number',
                body: 'Hashing your identity keys locally.',
              ),
            );
          }
          if (snapshot.hasError) {
            return _buildErrorBody(context, snapshot.error!);
          }
          return _buildBody(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildErrorBody(BuildContext context, Object error) {
    final isGroup = error is _UnsupportedGroupException;
    return Padding(
      padding: const EdgeInsets.all(VeilSpace.lg),
      child: VeilErrorState(
        title: isGroup
            ? 'Group safety numbers are not supported yet'
            : 'Could not load safety number',
        body: isGroup
            ? 'Safety numbers currently only work for direct conversations. Per-member verification for groups is planned.'
            : error.toString(),
        action: isGroup
            ? null
            : VeilButton(
                label: 'Retry',
                tone: VeilButtonTone.secondary,
                onPressed: _reload,
              ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, _SafetyNumbersData data) {
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
                'The identity key for this conversation is different from the one you verified on ${_formatDate(data.verification!.verifiedAt)}. This can happen if your peer reinstalled the app — or if someone is impersonating them. Verify again before trusting this chat.',
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
                  onPressed: _clearVerification,
                ),
              ],
            ),
          )
        else
          VeilButton(
            label: keyChanged ? 'Re-verify with new key' : 'Mark as verified',
            onPressed: () => _markVerified(data),
          ),
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

class _SafetyNumbersData {
  const _SafetyNumbersData({
    required this.peerHandle,
    required this.peerDisplayName,
    required this.peerIdentityPublicKey,
    required this.localIdentityPublicKey,
    required this.number,
    required this.verification,
  });

  final String peerHandle;
  final String? peerDisplayName;
  final String peerIdentityPublicKey;
  final String localIdentityPublicKey;
  final SafetyNumberResult number;
  final SafetyVerificationRecord? verification;

  String get peerDisplay =>
      (peerDisplayName != null && peerDisplayName!.isNotEmpty)
          ? peerDisplayName!
          : '@$peerHandle';
}

class _UnsupportedGroupException implements Exception {
  const _UnsupportedGroupException();
}

String _formatDate(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}
