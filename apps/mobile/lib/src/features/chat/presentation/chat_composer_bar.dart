import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/data/attach_flow.dart';
import '../../attachments/domain/attachment_rules.dart';
import '../../attachments/domain/outgoing_attachment.dart';
import '../../attachments/presentation/attach_file_dialog.dart';
import '../../attachments/presentation/attach_sheet.dart';
import '../../attachments/presentation/composer_drafts.dart';
import '../../attachments/presentation/photo_send_screen.dart';
import '../../conversations/presentation/peer_names.dart';
import 'chat_room_labels.dart';
import 'send_button.dart';

/// The composer at the foot of a chat: the plus that adds a photo or a
/// file, the draft and, once there is one, the send button. Typing tells
/// the peer. A send the messenger holds back for an identity change or a
/// held account keeps the draft for after the review, and such a chat
/// offers no plus. What is sent disappears after [messageTtl], which the
/// chat's bar shows.
///
/// The draft outlives the composer (composerDraftsProvider): a lock takes
/// the chat's screen down and an unlock builds it again. A photo or a file
/// picked while the lock came is held for the chat (AttachFlow) and offered
/// again once this composer is back.
class ChatComposerBar extends ConsumerStatefulWidget {
  const ChatComposerBar({
    super.key,
    required this.conversationId,
    required this.focusNode,
    required this.messageTtl,
    required this.busy,
  });

  final String conversationId;

  /// Owned by the screen, which focuses the composer from elsewhere too.
  final FocusNode focusNode;

  /// How long what is sent now lasts; null when it does not disappear.
  final Duration? messageTtl;

  /// Whether the messenger is busy, which disables sending.
  final bool busy;

  @override
  ConsumerState<ChatComposerBar> createState() => _ChatComposerBarState();
}

class _ChatComposerBarState extends ConsumerState<ChatComposerBar> {
  late final TextEditingController _messageController;
  late final ProviderContainer _container;
  late AttachFlow _flow;

  // Whether the draft has something to send, which shows the send button.
  bool _hasDraft = false;

  // Whether the attach sheet, a picker, the preview or the file dialog is
  // up, so a second one never opens over it.
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _messageController = TextEditingController(text: _container.read(composerDraftsProvider)[widget.conversationId]);
    _hasDraft = _messageController.text.trim().isNotEmpty;
    _messageController.addListener(_handleComposerChanged);
    _bindFlow();
  }

  @override
  void didUpdateWidget(covariant ChatComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId == widget.conversationId) return;
    _unbindFlow();
    _messageController
      ..removeListener(_handleComposerChanged)
      ..text = _container.read(composerDraftsProvider)[widget.conversationId] ?? ''
      ..addListener(_handleComposerChanged);
    _hasDraft = _messageController.text.trim().isNotEmpty;
    _bindFlow();
  }

  @override
  void dispose() {
    _unbindFlow();
    _messageController.dispose();
    super.dispose();
  }

  void _bindFlow() {
    _flow = _container.read(attachFlowProvider(widget.conversationId));
    _flow.held.addListener(_offerHeld);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerHeld());
  }

  // Taken down by a lock, the chat comes back after the unlock and offers
  // what is held; left, it drops it.
  void _unbindFlow() {
    _flow.held.removeListener(_offerHeld);
    if (!_container.read(appSessionProvider).locked) _flow.chatLeft();
  }

  void _handleComposerChanged() {
    final text = _messageController.text;
    final hasDraft = text.trim().isNotEmpty;
    if (hasDraft != _hasDraft) setState(() => _hasDraft = hasDraft);
    final id = widget.conversationId;
    _container.read(composerDraftsProvider.notifier).update((drafts) => {
          for (final MapEntry(:key, :value) in drafts.entries)
            if (key != id) key: value,
          if (text.isNotEmpty) id: text,
        });
    if (hasDraft) {
      ref.read(messengerControllerProvider).notifyTyping(widget.conversationId);
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }

    final controller = ref.read(messengerControllerProvider);
    await controller.sendText(
      conversationId: widget.conversationId,
      body: body,
      disappearAfter: widget.messageTtl,
    );
    // Held back by an identity change or a held account: the text stays for
    // after the review.
    if (controller.pendingIdentityChangeFor(widget.conversationId) == null &&
        controller.peerAccountHoldFor(widget.conversationId) == null) {
      _messageController.clear();
    }
  }

  Future<void> _attach() async {
    if (_attaching) return;
    _attaching = true;
    try {
      final source = await showAttachSheet(context);
      if (source == null || !mounted) return;
      final outcome = source == AttachSource.photos ? await _flow.pickPhoto() : await _flow.pickFile();
      if (!mounted) {
        if (outcome.pick case final pick?) _flow.hold(pick);
        return;
      }
      final l10n = AppLocalizations.of(context);
      switch (outcome.refusal) {
        case AttachRefusal.tooBig:
          showVeilToast(context, l10n.chatAttachTooBig(formatFileSize(kMaxFileBytes)));
        case AttachRefusal.photoFailed:
          showVeilToast(context, l10n.chatAttachPhotoFailed);
        case AttachRefusal.fileFailed:
          showVeilToast(context, l10n.chatAttachFileFailed);
        case null:
          if (outcome.pick case final pick?) await _offer(pick);
      }
    } finally {
      _attaching = false;
    }
  }

  // Offers the pick the flow held while this composer was away.
  void _offerHeld() {
    if (!mounted || _attaching || _flow.held.value == null) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final pick = _flow.takeHeld();
    if (pick == null) return;
    _attaching = true;
    unawaited(_offer(pick).whenComplete(() => _attaching = false));
  }

  // The preview for a photo, the confirm dialog for a file, then the send.
  // Closed by the user, the staged copy goes; taken down by a lock, the
  // pick is held and offered again after the unlock.
  Future<void> _offer(AttachPick pick) async {
    final OutgoingAttachment? attachment;
    switch (pick) {
      case PhotoPick():
        final choice = await Navigator.of(context, rootNavigator: true).push(PhotoSendScreen.route(pick.prepared));
        final prepared = await pick.prepared;
        if (prepared == null || choice == PhotoSendChoice.failed) {
          if (mounted) showVeilToast(context, AppLocalizations.of(context).chatAttachPhotoFailed);
          return;
        }
        attachment = choice == PhotoSendChoice.send
            ? OutgoingAttachment.photo(path: pick.stagedPath, contentType: prepared.contentType)
            : null;
      case FilePick():
        final send = await confirmSendFile(
          context,
          name: pick.name,
          chat: _chatTitle(),
          sizeBytes: pick.sizeBytes,
          keepsMetadata: pick.keepsMetadata,
        );
        attachment = send
            ? OutgoingAttachment.file(path: pick.stagedPath, name: pick.name, contentType: contentTypeForName(pick.name))
            : null;
    }
    if (attachment == null) {
      if (_container.read(appSessionProvider).locked) {
        _flow.hold(pick);
      } else {
        await _flow.discard(pick);
      }
      return;
    }
    // A chat held meanwhile seals nothing: the send deletes the staged copy
    // and the chat's banner says why.
    await _container.read(messengerControllerProvider).sendAttachment(
          conversationId: widget.conversationId,
          attachment: attachment,
          disappearAfter: widget.messageTtl,
        );
  }

  // The chat's title as its bar shows it.
  String _chatTitle() {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(messengerControllerProvider);
    final conversation = controller.conversationById(widget.conversationId);
    if (conversation == null) return l10n.chatTitleFallback;
    return conversationTitle(l10n, conversation, ref.read(peerNamesProvider), localUserId: controller.localUserId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final id = widget.conversationId;
    // A chat whose peer is in question sends nothing new until it is
    // settled, so it offers nothing to attach.
    final held = ref.watch(messengerControllerProvider
        .select((messenger) => messenger.pendingIdentityChangeFor(id) != null || messenger.peerAccountHoldFor(id) != null));
    return VeilComposer(
      controller: _messageController,
      focusNode: widget.focusNode,
      enabled: !widget.busy,
      onSubmit: _sendMessage,
      label: l10n.chatComposeHint,
      leading: held
          ? null
          : IconButton(
              key: const ValueKey('composer-attach'),
              tooltip: l10n.chatAttachAction,
              onPressed: widget.busy ? null : _attach,
              icon: const Icon(Icons.add, size: 24),
              color: palette.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
      // A disabled composer says why in its hint and offers no send.
      trailing: SendButton(
        onPressed: widget.busy || !_hasDraft ? null : _sendMessage,
        semanticLabel: l10n.chatSendAction,
      ),
    );
  }
}
