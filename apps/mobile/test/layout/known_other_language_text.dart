// The allow-list of the layout gate's language check (phone_layout_test.dart,
// support/language_probe.dart).

/// Screens that show text of their own in the language the run is not in,
/// by screen file, with how many different texts each shows per language of
/// the run: `{'ko': 3}` is three English texts in a Korean run.
///
/// The gate fails for a screen that is not listed and shows one, for a
/// listed screen that shows more than its number, and for one that shows
/// fewer, so this list can only shrink. To fix a screen: move its strings
/// to app_en.arb and app_ko.arb, run `flutter test test/layout`, then lower
/// the number to what the gate reports, or delete the line when it reports
/// none. Never raise a number and never add a line.
///
/// `flutter test test/layout --dart-define=SHOTS_DIR=<dir>` lists the texts
/// themselves in `<dir>/report.json` (`otherLanguageTexts`).
///
/// One line per screen, grouped by who owns the screen.
const knownOtherLanguageText = <String, Map<String, int>>{
  // --- Onboarding, account and device transfer.
  'device_transfer_screen.dart': {'ko': 2},

  // --- Chat and conversation list, starting a chat or a group.
  'start_group_screen.dart': {'ko': 1},

  // --- Settings, security status, safety numbers, contacts, one-time link.

  // --- Switched-off surfaces: localized by whoever switches one on.
  'ai_chat_screen.dart': {'ko': 9},
  'call_screen.dart': {'ko': 6},
  'media_picker_screen.dart': {'ko': 6},
  'sticker_picker_screen.dart': {'ko': 10},
  'stories_screen.dart': {'ko': 10},
  'story_viewer_screen.dart': {'ko': 2},
  'voice_recorder_screen.dart': {'ko': 3},
};
