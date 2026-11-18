import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/chat_bar.dart';
import '../../safety/presentation/mute_sheet.dart';
import '../data/veil_messenger_controller.dart';

/// What a long press on a Chats row offers, in the words of Telegram and
/// WhatsApp: "Mark as read" while the chat is unread or marked unread, else
/// "Mark as unread" (not for the chat open beside the list, which would be
/// read again at once: [open]); then "Mute notifications" or "Unmute". A
/// screen reader offers the same as actions on the row.
///
/// Marking is local: "Mark as unread" calls nothing and takes back no read
/// receipt; "Mark as read" sends the one receipt opening the chat would
/// have sent, and none from a chat whose receipts are withheld.
List<ChatMenuEntry> conversationRowActions(
  BuildContext context,
  VeilMessengerController controller, {
  required String conversationId,
  required bool muted,
  required bool open,
}) {
  final l10n = AppLocalizations.of(context);
  final reads = controller.reads;
  return [
    if (reads.isUnread(conversationId))
      ChatMenuEntry(key: 'read', label: l10n.conversationsMarkRead, onSelected: () => reads.markRead(conversationId))
    else if (!open)
      ChatMenuEntry(
        key: 'unread',
        label: l10n.conversationsMarkUnread,
        onSelected: () => reads.markUnread(conversationId),
      ),
    if (muted)
      ChatMenuEntry(
        key: 'unmute',
        label: l10n.muteUnmute,
        onSelected: () => unmuteConversation(context, conversationId),
      )
    else
      ChatMenuEntry(key: 'mute', label: l10n.muteTitle, onSelected: () => showMuteSheet(context, conversationId)),
  ];
}

/// The row's actions as a screen reader offers them.
Map<CustomSemanticsAction, VoidCallback> conversationRowSemanticActions(List<ChatMenuEntry> actions) => {
      for (final action in actions) CustomSemanticsAction(label: action.label): action.onSelected,
    };

/// The menu a long press on a Chats row opens, drawn as the chat bar's menu
/// is (44dp text items, no glyphs), at the row's end edge over its lower
/// half: [anchor] is the row on screen.
Future<void> showConversationRowMenu(BuildContext context, {required Rect anchor, required List<ChatMenuEntry> actions}) async {
  final palette = context.veilPalette;
  final textStyle = Theme.of(context).textTheme.bodyLarge;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final corner = Offset(rtl ? anchor.left : anchor.right, anchor.center.dy);
  VeilHaptics.selection();
  final key = await showMenu<String>(
    context: context,
    color: palette.surfaceRaised,
    position: RelativeRect.fromRect(corner & Size.zero, Offset.zero & overlay.size),
    items: [
      for (final action in actions)
        PopupMenuItem<String>(
          key: ValueKey('conversation-menu-${action.key}'),
          value: action.key,
          height: 44,
          child: Text(action.label, style: textStyle),
        ),
    ],
  );
  // Found by its key, as the chat bar's menu finds its entries.
  for (final action in actions) {
    if (action.key == key) return action.onSelected();
  }
}
