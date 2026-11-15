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
  'device_transfer_screen.dart': {
    'ko': {
      'VEIL New Device',
      'VEIL_TRANSFER::<sessionId>::<token>',
    },
  },

  // --- Chat and conversation list, starting a chat or a group.
  'start_group_screen.dart': {
    'ko': {'Signal Boost'},
  },

  // --- Settings, security status, safety numbers, contacts, one-time link.

  // --- Switched-off surfaces (calls, media, voice, emoji, assistant,
  // stories, attachments).
};
