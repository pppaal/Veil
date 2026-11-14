import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/features/ai/ai_feature.dart';
import 'package:veil_mobile/src/features/ai/presentation/ai_chat_screen.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/attachments/attachments_feature.dart';
import 'package:veil_mobile/src/features/attachments/presentation/attachment_preview_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/create_account_screen.dart';
import 'package:veil_mobile/src/features/calls/calls_feature.dart';
import 'package:veil_mobile/src/features/calls/presentation/call_history_screen.dart';
import 'package:veil_mobile/src/features/calls/presentation/call_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_status_banners.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/reaction_chips_row.dart';
import 'package:veil_mobile/src/features/chat/presentation/typing_indicator.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/features/media/media_feature.dart';
import 'package:veil_mobile/src/features/media/presentation/media_picker_screen.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/privacy_consent_screen.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/splash_screen.dart';
import 'package:veil_mobile/src/features/profile/presentation/profile_screen.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';
import 'package:veil_mobile/src/features/secret_link/presentation/one_time_link_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_status_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/features/stickers/presentation/sticker_picker_screen.dart';
import 'package:veil_mobile/src/features/stickers/stickers_feature.dart';
import 'package:veil_mobile/src/features/stories/presentation/stories_screen.dart';
import 'package:veil_mobile/src/features/stories/presentation/story_viewer_screen.dart';
import 'package:veil_mobile/src/features/stories/stories_feature.dart';
import 'package:veil_mobile/src/features/voice/presentation/voice_recorder_screen.dart';
import 'package:veil_mobile/src/features/voice/voice_feature.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'layout_seed.dart';
import 'layout_world.dart';
import 'phone_layout_probe.dart';

// Every screen of the app as the phone layout gate opens it: where it lives
// in the route table, the account it needs, and the state it is shown in.
// A screen file under lib/src/features/*/presentation with no case here
// fails the gate (see phone_layout_test.dart).

/// The least share of the screen height the messages of a chat and the
/// rows of the conversation list must get in their everyday state.
const double minPrimaryContentShare = 0.45;

/// What the messages must keep, in logical pixels, when the keyboard or a
/// stack of warnings takes most of the screen: room for one short message.
const double minSqueezedMessagesExtent = 96;

class ScreenCase {
  const ScreenCase(
    this.id, {
    required this.screen,
    required this.file,
    required this.location,
    this.account = LayoutAccount.signedIn,
    this.extra,
    this.attention = const ChatAttention(),
    this.keyboardHeight = 0,
    this.bootstrapping = false,
    this.transferStarted = false,
    this.withGroup = false,
    this.textScale = 1,
    this.sizes = phoneSizes,
    this.chatInPane = false,
    this.primaryExtent,
    this.minPrimaryShare,
    this.minPrimaryExtent,
    this.primaryAction,
    this.settle,
  }) : assert((minPrimaryShare == null && minPrimaryExtent == null) || primaryExtent != null);

  /// Names the case in test names, the allow-list and PNG file names.
  final String id;

  /// The screen's widget, which must be on screen once the case is open.
  final Type screen;

  /// The screen's file under lib/src/features/*/presentation.
  final String file;

  /// Where the router opens.
  final String location;
  final Object? extra;
  final LayoutAccount account;
  final ChatAttention attention;

  /// Height of the software keyboard, when the case has it open.
  final double keyboardHeight;

  /// App startup never finishes (the splash screen's own state).
  final bool bootstrapping;

  /// This device already opened a transfer session.
  final bool transferStarted;

  /// The account has a group conversation, the newest of its list.
  final bool withGroup;

  /// The system's text size setting; 1 is the default size.
  final double textScale;

  /// The screen sizes the case is rendered at.
  final List<PhoneSize> sizes;

  /// Whether every control of the case must measure 44x44 or more.
  bool get holdsTapTargets => !tapTargetExemptScreens.contains(file);

  /// True for a case that opens the chat of the cases beside the list, in
  /// the second pane of the wide shell, where [screen] is the list.
  final bool chatInPane;

  /// Whether the case has the chat of [attention] on screen, as its own
  /// screen or in the second pane.
  bool get showsChat => screen == ChatRoomScreen || chatInPane;

  /// How many warning actions the case's chat must show, each wholly on
  /// screen: one per warning of [attention] that asks for a decision.
  int get warningActionCount => showsChat ? attention.warningActionCount : 0;

  /// Height in logical pixels the screen's primary content has on screen:
  /// the messages of a chat, the rows of the conversation list. Measured
  /// and reported whether or not the case sets a minimum.
  final double Function(WidgetTester tester)? primaryExtent;

  /// The share of the screen height [primaryExtent] must reach, if any.
  final double? minPrimaryShare;

  /// The height in logical pixels [primaryExtent] must reach, if any.
  final double? minPrimaryExtent;

  /// The control the screen is for: its first input, or its primary button.
  /// When the case opens with the keyboard closed, it must lie wholly on
  /// the first screenful, where a tap reaches it, at 390x844 and 412x915;
  /// at 360x640 its top edge must (see [primaryActionProblem]).
  final Finder Function()? primaryAction;

  /// Brings the screen to the state the case is about, after its first
  /// frames.
  final Future<void> Function(WidgetTester tester)? settle;
}

/// The screens whose controls the gate does not hold to 44x44, each with
/// what is smaller there. Every other screen is held to it. This set may
/// only shrink: a new screen is held from the start.
const tapTargetExemptScreens = {
  // The emoji and sticker grid packs eight cells of about 33 px into a row.
  'sticker_picker_screen.dart',
};

/// The text size of the larger-text cases: the step most people who enlarge
/// their text choose.
const double largerText = 1.3;

/// Routes to the screens of the features this build has switched off, which
/// the app's own route table leaves out (see each `*_feature.dart`). The
/// gate still renders those screens, and their tests still open them,
/// through these. A feature that is switched on drops out of this list: its
/// routes are the app's again.
final List<RouteBase> layoutOnlyRoutes = [
  if (!kStoriesEnabled) ...[
    GoRoute(path: '/stories', builder: (_, __) => const StoriesScreen()),
    GoRoute(
      path: '/story-viewer/:userId',
      builder: (_, state) => StoryViewerScreen(authorUserId: state.pathParameters['userId']!),
    ),
  ],
  if (!kCallsEnabled) ...[
    GoRoute(path: '/calls', builder: (_, __) => const CallHistoryScreen()),
    GoRoute(
      path: '/call/:conversationId',
      builder: (_, state) => CallScreen(
        contactName: switch (state.extra) { {'name': final String name} => name, _ => '' },
      ),
    ),
  ],
  if (!kAttachmentsEnabled)
    GoRoute(
      path: '/attachment/:conversationId',
      builder: (_, state) => AttachmentPreviewScreen(conversationId: state.pathParameters['conversationId']!),
    ),
  if (!kMediaPickerEnabled) GoRoute(path: '/media/:conversationId', builder: (_, __) => const MediaPickerScreen()),
  if (!kVoiceMessagesEnabled)
    GoRoute(path: '/voice/:conversationId', builder: (_, __) => const VoiceRecorderScreen()),
  if (!kStickerPickerEnabled)
    GoRoute(path: '/stickers/:conversationId', builder: (_, __) => const StickerPickerScreen()),
  if (!kAssistantEnabled) GoRoute(path: '/ai-chat', builder: (_, __) => const AiChatScreen()),
];

const _signedOut = LayoutAccount.signedOut;
const _chat = '/chat/$chatConversationId';

const List<ScreenCase> screenCases = [
  // Before there is an account.
  ScreenCase('splash',
      screen: SplashScreen, file: 'splash_screen.dart', location: '/splash', account: _signedOut, bootstrapping: true),
  ScreenCase('privacy-consent',
      screen: PrivacyConsentScreen,
      file: 'privacy_consent_screen.dart',
      location: '/privacy-consent',
      account: _signedOut,
      primaryAction: _primaryButton),
  ScreenCase('onboarding-warning',
      screen: OnboardingWarningScreen,
      file: 'onboarding_warning_screen.dart',
      location: '/onboarding',
      account: _signedOut),
  ScreenCase('create-account',
      screen: CreateAccountScreen,
      file: 'create_account_screen.dart',
      location: '/create-account',
      account: _signedOut,
      primaryAction: _primaryButton),
  ScreenCase('choose-handle',
      screen: ChooseHandleScreen,
      file: 'choose_handle_screen.dart',
      location: '/choose-handle',
      account: _signedOut,
      primaryAction: _primaryButton),
  ScreenCase('device-transfer-new-device',
      screen: DeviceTransferScreen,
      file: 'device_transfer_screen.dart',
      location: '/device-transfer',
      account: _signedOut,
      primaryAction: _firstInput),
  ScreenCase('app-lock',
      screen: AppLockScreen,
      file: 'app_lock_screen.dart',
      location: '/lock',
      account: LayoutAccount.locked,
      primaryAction: _primaryButton),

  // The conversation list, in the main shell with its bottom bar: with
  // conversations, with none, and while searching.
  ScreenCase(
    'conversation-list',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    primaryExtent: conversationRowsExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'conversation-list-empty',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    account: LayoutAccount.signedInEmpty,
  ),
  ScreenCase(
    'conversation-list-search',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    primaryExtent: conversationRowsExtent,
    settle: _searchConversations,
  ),

  // A chat: its everyday state, before the first message, with the
  // keyboard open, and with the warnings a chat can carry.
  ScreenCase(
    'chat-room',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'chat-room-empty',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$emptyChatConversationId',
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'chat-room-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'chat-room-warnings',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(identityChanged: true, failedSends: 2),
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),

  // The states the first gate left out: nothing sent yet and the keyboard
  // up, warnings and the keyboard together (the least room a chat ever
  // has), a held account (the longest warning) with and without the
  // keyboard, search open in the bar, a disappearing timer, and the timer's
  // sheet.
  ScreenCase(
    'chat-room-empty-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$emptyChatConversationId',
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'chat-room-warnings-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(identityChanged: true, failedSends: 2),
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'chat-room-account-hold',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(accountHeld: true),
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'chat-room-account-hold-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(accountHeld: true),
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'chat-room-search',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _searchChat,
  ),
  ScreenCase(
    'chat-room-timer',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$timerChatConversationId',
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'chat-room-timer-sheet',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    settle: _openTimerSheet,
  ),

  ScreenCase(
    'chat-room-reaction-sheet',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    settle: _openReactionSheet,
  ),
  ScreenCase(
    'conversation-list-new-menu',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    settle: _openNewConversationMenu,
  ),

  // The three screens a user spends the day in, with larger text.
  ScreenCase(
    'chat-room-larger-text',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(identityChanged: true),
    textScale: largerText,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
  ScreenCase(
    'conversation-list-larger-text',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    textScale: largerText,
    primaryExtent: conversationRowsExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'app-lock-larger-text',
    screen: AppLockScreen,
    file: 'app_lock_screen.dart',
    location: '/lock',
    account: LayoutAccount.locked,
    textScale: largerText,
  ),

  // Reached from a chat.
  ScreenCase('safety-numbers',
      screen: SafetyNumbersScreen,
      file: 'safety_numbers_screen.dart',
      location: '/safety-numbers/$chatConversationId',
      settle: _awaitSafetyNumber),
  ScreenCase('safety-numbers-identity-change',
      screen: SafetyNumbersScreen,
      file: 'safety_numbers_screen.dart',
      location: '/safety-numbers/$chatConversationId',
      attention: ChatAttention(identityChanged: true),
      settle: _awaitSafetyNumber),
  ScreenCase('attachment-preview',
      screen: AttachmentPreviewScreen,
      file: 'attachment_preview_screen.dart',
      location: '/attachment/$chatConversationId'),
  ScreenCase('media-picker',
      screen: MediaPickerScreen, file: 'media_picker_screen.dart', location: '/media/$chatConversationId'),
  ScreenCase('voice-recorder',
      screen: VoiceRecorderScreen, file: 'voice_recorder_screen.dart', location: '/voice/$chatConversationId'),
  ScreenCase('sticker-picker',
      screen: StickerPickerScreen, file: 'sticker_picker_screen.dart', location: '/stickers/$chatConversationId'),
  ScreenCase(
    'call',
    screen: CallScreen,
    file: 'call_screen.dart',
    location: '/call/$chatConversationId',
    extra: {'name': 'Selene Park'},
    settle: _untilCallConnects,
  ),

  // Starting a conversation.
  ScreenCase('start-direct-chat',
      screen: StartDirectChatScreen,
      file: 'start_direct_chat_screen.dart',
      location: '/start-chat',
      primaryAction: _primaryButton),
  ScreenCase('start-group',
      screen: StartGroupScreen,
      file: 'start_group_screen.dart',
      location: '/start-group',
      primaryAction: _primaryButton),
  ScreenCase('one-time-link',
      screen: OneTimeLinkScreen,
      file: 'one_time_link_screen.dart',
      location: '/secret-link',
      primaryAction: _primaryButton),

  // The other tabs.
  ScreenCase('contacts',
      screen: ContactsScreen,
      file: 'contacts_screen.dart',
      location: '/contacts',
      primaryAction: _addContact,
      primaryExtent: contactRowsExtent,
      minPrimaryShare: minPrimaryContentShare),
  ScreenCase('contacts-add-sheet',
      screen: ContactsScreen,
      file: 'contacts_screen.dart',
      location: '/contacts',
      keyboardHeight: 300,
      settle: _openAddContactSheet),
  ScreenCase('contacts-actions-sheet',
      screen: ContactsScreen,
      file: 'contacts_screen.dart',
      location: '/contacts',
      settle: _openContactActionsSheet),
  ScreenCase('call-history', screen: CallHistoryScreen, file: 'call_history_screen.dart', location: '/calls'),
  ScreenCase('stories', screen: StoriesScreen, file: 'stories_screen.dart', location: '/stories'),
  ScreenCase('story-viewer',
      screen: StoryViewerScreen, file: 'story_viewer_screen.dart', location: '/story-viewer/user-$peerHandle'),

  // Account, device and security.
  ScreenCase('settings',
      screen: SettingsScreen, file: 'settings_screen.dart', location: '/settings', primaryAction: _firstSetting),
  ScreenCase('profile', screen: ProfileScreen, file: 'profile_screen.dart', location: '/profile'),
  ScreenCase('security-status',
      screen: SecurityStatusScreen, file: 'security_status_screen.dart', location: '/security-status'),
  ScreenCase('device-transfer-old-device',
      screen: DeviceTransferScreen,
      file: 'device_transfer_screen.dart',
      location: '/device-transfer',
      transferStarted: true,
      primaryAction: _firstInput),
  ScreenCase('ai-chat', screen: AiChatScreen, file: 'ai_chat_screen.dart', location: '/ai-chat'),

  // States the gate did not open before: a group (its chat, its row in the
  // list, the safety numbers of its members), a message from a legacy frame
  // with its badge, reactions under bubbles, the peer typing, a search that
  // found messages, and the least room a chat ever has with larger text.
  ScreenCase(
    'chat-room-group',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$groupConversationId',
    withGroup: true,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectGroupMessages,
  ),
  ScreenCase(
    'conversation-list-group',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    withGroup: true,
    primaryExtent: conversationRowsExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase('safety-numbers-group',
      screen: SafetyNumbersScreen,
      file: 'safety_numbers_screen.dart',
      location: '/safety-numbers/$groupConversationId',
      withGroup: true,
      settle: _awaitSafetyNumber),
  // The peer's key changed in the group: their 1:1 holds no change, and its
  // safety number says where the change waits instead of "verified".
  ScreenCase('safety-numbers-change-elsewhere',
      screen: SafetyNumbersScreen,
      file: 'safety_numbers_screen.dart',
      location: '/safety-numbers/$chatConversationId',
      withGroup: true,
      attention: ChatAttention(identityChangedInGroup: true),
      settle: _awaitChangeElsewhere),
  ScreenCase(
    'chat-room-legacy-badge',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(legacyMessage: true),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectLegacyBadge,
  ),
  ScreenCase(
    'chat-room-reactions',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _reactToMessages,
  ),
  ScreenCase(
    'chat-room-typing',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(peerTyping: true),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectTypingIndicator,
  ),
  ScreenCase(
    'chat-room-search-hits',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _searchChatForHits,
  ),
  ScreenCase(
    'chat-room-warnings-keyboard-larger-text',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(identityChanged: true, failedSends: 2),
    keyboardHeight: 300,
    textScale: largerText,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
  ),
];

const _wideSizes = [wideSmall, wideLarge];
const _tablet = [tabletUpright];

/// The cases wider than a phone. From 1120 px the conversations shell shows
/// the list and the open chat side by side; a tablet held upright is too
/// narrow for that and opens the chat on top, like a phone. Held to what a
/// phone's chat is held to: layout errors, the messages keeping their share
/// of the height, every warning's action wholly on screen, and tap targets
/// (1280x800 is also a tablet on its side).
const List<ScreenCase> wideCases = [
  ScreenCase(
    'wide-chat',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    sizes: _wideSizes,
    chatInPane: true,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _openChatPane,
  ),
  ScreenCase(
    'wide-chat-warnings',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(identityChanged: true, failedSends: 2),
    sizes: _wideSizes,
    chatInPane: true,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _openChatPane,
  ),
  ScreenCase(
    'tablet-chat',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    sizes: _tablet,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'tablet-chat-warnings',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    attention: ChatAttention(identityChanged: true, failedSends: 2),
    sizes: _tablet,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
];

/// Every case of the gate, phone and wide.
const List<ScreenCase> allCases = [...screenCases, ...wideCases];

// The primary button of a screen: the filled one, the first if a screen has
// more.
Finder _primaryButton() => find.byType(FilledButton);

// The first field of a screen.
Finder _firstInput() => find.byType(TextField);

// What adds a contact, wherever the screen puts it.
Finder _addContact() => find.byIcon(Icons.person_add_outlined);

// The first control of the settings screen that changes a setting: the
// theme selector or a switch, whichever the screen puts first. A row that
// only leads to another screen (the profile, the security status) is not it.
Finder _firstSetting() =>
    find.byWidgetPredicate((widget) => widget is Switch || widget is SegmentedButton<ThemeMode>);

/// Why the first control [finder] finds is not on the first screenful, or
/// null when it is. On the two larger phones all of it must be on screen where a
/// tap reaches it. A 360x640 screen has room for less: there its top edge
/// must be on screen and take a tap, so that the control is at least begun
/// before the fold. A control a lazy list has not built is below the fold.
String? primaryActionProblem(WidgetTester tester, Finder finder, PhoneSize size) {
  final found = finder.evaluate();
  if (found.isEmpty) return 'is not built on the first screenful';
  final box = found.first.renderObject! as RenderBox;
  if (size != phoneSmall) return whyNotWhollyTappable(tester, box);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final top = rect.topCenter.translate(0, 1);
  if (rect.top < 0 || top.dy >= screenHeight(tester)) return 'starts outside the screen at $rect';
  final hit = tester.hitTestOnBinding(top);
  return hit.path.any((entry) => entry.target == box) ? null : 'takes no tap at its top edge ($top); it is at $rect';
}

/// The height the chat's message area has on screen.
double chatMessagesExtent(WidgetTester tester) {
  final list = find.byType(ChatMessageList);
  if (list.evaluate().isEmpty) return 0;
  return visibleRect(tester, tester.renderObject<RenderBox>(list.first)).height;
}

/// The height conversations can use when the list opens: from the top of
/// the first conversation row to the bottom of the list it scrolls in.
/// What sits above the first row (a header, a search field) is not it,
/// whether it scrolls with the rows or stays put.
double conversationRowsExtent(WidgetTester tester) => _rowsExtent(tester, find.byType(VeilConversationCard));

/// The same for the contacts: from the top of the first contact's row to
/// the bottom of the list it scrolls in.
double contactRowsExtent(WidgetTester tester) => _rowsExtent(tester, find.byType(VeilListTileCard));

double _rowsExtent(WidgetTester tester, Finder rows) {
  if (rows.evaluate().isEmpty) return 0;
  final firstRow = tester.renderObject<RenderBox>(rows.first);
  final RenderObject? viewport = RenderAbstractViewport.maybeOf(firstRow);
  if (viewport is! RenderBox) return 0;
  final list = visibleRect(tester, viewport);
  final top = firstRow.localToGlobal(Offset.zero).dy.clamp(list.top, list.bottom);
  return list.bottom - top;
}

/// The actions of the warnings a chat shows above its messages.
Finder chatWarningActions() =>
    find.descendant(of: find.byType(ChatStatusBanners), matching: find.byType(TextButton));

Future<void> _searchConversations(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, conversationSearchQuery);
  // The archive search waits 180 ms for the typing to stop.
  await pumpFrames(tester, frames: 4);
}

Future<void> _searchChat(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.search_rounded));
  await pumpFrames(tester, frames: 2);
  // Typed where the focus is: opening the search moves it to the bar's field.
  tester.testTextInput.enterText(chatSearchQuery);
  // The search waits 180 ms for the typing to stop.
  await pumpFrames(tester, frames: 4);
}

// The search as it stands once the keyboard is put away: the matches have
// the whole height.
Future<void> _searchChatForHits(WidgetTester tester) async {
  await _searchChat(tester);
  expect(find.byType(MessageBubble), findsWidgets, reason: 'the search found no message');
  expect(find.byType(MessageBubble).evaluate().length, lessThan(chatLineCount - 1),
      reason: 'the search did not narrow the messages');
}

Future<void> _expectGroupMessages(WidgetTester tester) async {
  expect(find.byType(MessageBubble), findsNWidgets(groupLineCount), reason: 'the group chat did not open its messages');
}

Future<void> _expectLegacyBadge(WidgetTester tester) async {
  // The badge sits on the peer's first message, at the top of the history.
  await tester.dragUntilVisible(
    find.descendant(of: find.byType(MessageBubble), matching: find.byType(VeilStatusPill)),
    find.byType(ChatMessageList),
    const Offset(0, 200),
  );
  await pumpFrames(tester, frames: 2);
}

// A reaction on two of the messages on screen, given the way a user gives
// one: a long press, then the emoji.
Future<void> _reactToMessages(WidgetTester tester) async {
  for (final (bubble, emoji) in [(0, '\u{1F44D}'), (1, '\u{2764}\u{FE0F}')]) {
    // The card, not its row: a short message does not reach the middle.
    // The list is built from its end, so the first cards are the newest.
    await tester.longPress(find.byType(VeilMessageBubbleCard).at(bubble));
    await pumpFrames(tester, frames: 4);
    await tester.tap(find.descendant(of: find.byType(ReactionPickerWidget), matching: find.text(emoji)));
    await pumpFrames(tester, frames: 6);
  }
  expect(find.byType(ReactionChipsRow), findsNWidgets(2), reason: 'the reactions did not show under their messages');
}

Future<void> _expectTypingIndicator(WidgetTester tester) async {
  expect(find.descendant(of: find.byType(TypingIndicator), matching: find.byType(Text)), findsOneWidget,
      reason: 'the typing indicator is not on screen');
}

// The two-pane shell with the chat of the cases in its second pane.
Future<void> _openChatPane(WidgetTester tester) async {
  bool open() => tester
      .widgetList<ChatRoomScreen>(find.byType(ChatRoomScreen))
      .any((chat) => chat.conversationId == chatConversationId);
  await pumpFrames(tester, frames: 4);
  if (!open()) {
    await tester.tap(find.text(peerNames[peerHandle]!).first);
    await pumpFrames(tester, frames: 6);
  }
  expect(open(), isTrue, reason: 'the second pane did not open the chat');
}

Future<void> _openTimerSheet(WidgetTester tester) async {
  // A disappearing message carries the same icon: the bar's is the button.
  await tester.tap(find.widgetWithIcon(IconButton, Icons.timer_outlined));
  await pumpFrames(tester, frames: 4);
  expect(find.byType(BottomSheet), findsOneWidget, reason: 'the timer sheet did not open');
}

Future<void> _openReactionSheet(WidgetTester tester) async {
  await tester.longPress(find.byType(MessageBubble).first);
  await pumpFrames(tester, frames: 4);
  expect(find.byType(ReactionPickerWidget), findsOneWidget, reason: 'the reaction sheet did not open');
}

Future<void> _openNewConversationMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_square));
  await pumpFrames(tester, frames: 3);
  expect(find.byType(PopupMenuItem<String>), findsNWidgets(2), reason: 'the menu did not open');
}

Future<void> _openAddContactSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.person_add_outlined));
  await pumpFrames(tester, frames: 4);
  expect(find.byType(BottomSheet), findsOneWidget, reason: 'the add-contact sheet did not open');
}

Future<void> _openContactActionsSheet(WidgetTester tester) async {
  await tester.tap(find.byType(VeilListTileCard).first);
  await pumpFrames(tester, frames: 4);
  expect(find.byType(BottomSheet), findsOneWidget, reason: 'the contact sheet did not open');
}

// The safety number is derived on a background isolate, which only real
// time moves forward.
Future<void> _awaitSafetyNumber(WidgetTester tester) async {
  final loading = find.byType(VeilLoadingBlock);
  for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(loading, findsNothing, reason: 'the safety number never loaded');
  expect(find.byType(VeilErrorState), findsNothing, reason: 'the safety number failed to load');
  await pumpFrames(tester, frames: 3);
}

Future<void> _awaitChangeElsewhere(WidgetTester tester) async {
  await _awaitSafetyNumber(tester);
  // The page opens on the notice; a verified contact's page has none.
  expect(find.byType(VeilInlineBanner), findsOneWidget, reason: 'the page does not say a change waits elsewhere');
}

// The call screen plays dialing (2 s) and ringing (3 s) before the state a
// call spends its time in.
Future<void> _untilCallConnects(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 1));
}
