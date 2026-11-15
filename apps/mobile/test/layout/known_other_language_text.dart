// The allow-list of the layout gate's language check (phone_layout_test.dart,
// support/language_probe.dart).

/// Screens that show text of their own in the language the run is not in,
/// by screen file, with the texts each shows per language of the run:
/// `{'ko': {'Send'}}` is the English text "Send" in a Korean run. A text is
/// listed as the gate reports it: what the widget draws, cut to 80
/// characters.
///
/// The gate fails for a text that is not listed here, on whatever screen,
/// and for a listed text its screen no longer shows, so this list can only
/// shrink, and one text cannot be swapped for another. To fix a screen:
/// move its strings to app_en.arb and app_ko.arb, run
/// `flutter test test/layout`, and delete the lines the gate says are no
/// longer shown (the screen's entry with the last of them). Never add a
/// line.
///
/// A run of only some cases (`--plain-name`) still fails on a text that is
/// not listed; only a full run can say a listed text is gone.
///
/// One entry per screen, grouped by who owns the screen.
const knownOtherLanguageText = <String, Map<String, Set<String>>>{
  // --- Onboarding, account and device transfer.

  // --- Chat and conversation list, starting a chat or a group.
  'start_group_screen.dart': {
    'ko': {'Signal Boost'},
  },

  // --- Settings, security status, safety numbers, contacts, one-time link.

  // --- Switched-off surfaces: localized by whoever switches one on.
  'ai_chat_screen.dart': {
    'ko': {
      'Ask',
      'Ask about privacy, security, or VEIL features.',
      'Local',
      'MESSAGES',
      'MODEL',
      'PRIVACY',
      'Scripted',
      'This is a scripted preview of VEIL Assistant. It answers a few privacy and secur…',
      'VEIL Assistant',
    },
  },
  'call_screen.dart': {
    'ko': {
      'Calls are routed peer-to-peer when possible. Relay fallback is encrypted.',
      'Connected 00:02',
      'End',
      'Mute',
      'Speaker',
      'Video',
    },
  },
  'media_picker_screen.dart': {
    'ko': {
      'ENCRYPTED MEDIA',
      'Media',
      'Media is encrypted locally before upload. The relay never sees plaintext.',
      'Select media to send',
      'Send encrypted media',
      'Send encrypted media through the opaque relay. Files are sealed on-device before…',
    },
  },
  'sticker_picker_screen.dart': {
    'ko': {
      'ALL EMOJI',
      'Animals',
      'Emoji',
      'Food',
      'GIFs',
      'People',
      'RECENTLY USED',
      'Search emoji and stickers',
      'Smileys',
      'Stickers',
    },
  },
  'stories_screen.dart': {
    'ko': {
      '2h ago',
      '3 views',
      '3h ago',
      '4 views',
      'Feed',
      'My Story',
      'Recent stories',
      'Stories',
      'Stories expire after 24 hours. Content is stored locally until expiration.',
      'Text update',
    },
  },
  'story_viewer_screen.dart': {
    'ko': {
      '3h ago',
      'Reply to story…',
    },
  },
  'voice_recorder_screen.dart': {
    'ko': {
      'Tap to record',
      'Voice Message',
      'Voice data is encrypted on this device before relay.',
    },
  },
};
