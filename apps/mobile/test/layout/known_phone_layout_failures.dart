import 'support/phone_layout_probe.dart';

// The allow-list of the layout gate (phone_layout_test.dart).

const _small = [phoneSmall];
const _phones = phoneSizes;
const _both = ['en', 'ko'];

/// A case that is known not to fit, and how it fails.
class KnownPhoneLayoutFailure {
  const KnownPhoneLayoutFailure(
    this.caseId,
    this.sizes,
    this.locales,
    this.defects,
    this.reason, {
    this.light = false,
  });

  /// A ScreenCase id from support/screen_cases.dart.
  final String caseId;

  /// The sizes and languages it fails at, in exactly this way.
  final List<PhoneSize> sizes;
  final List<String> locales;

  /// Exactly the defects the case shows today.
  final Set<LayoutDefect> defects;
  final String reason;

  /// Whether this is the case's light-theme render (390x844, ko).
  final bool light;
}

/// Screens that do not fit. The gate fails for any failing case that is not
/// listed here, and for any listed case that passes or fails in another way
/// than listed, so this list can only shrink.
///
/// One line covers every size and language of a case that fails the same
/// way. To fix a case: change the screen, run `flutter test test/layout`,
/// and delete the line (or the sizes and languages that now pass) when the
/// gate says the case fits. Never add a line for a new defect: fix it.
///
/// The lines are grouped by who owns the screen, so that two people fixing
/// different screens edit different lines.
const knownPhoneLayoutFailures = <KnownPhoneLayoutFailure>[
  // --- Onboarding, account and device transfer.

  // --- Chat and conversation list (phone and wide), starting a chat or a group.
  KnownPhoneLayoutFailure('start-group', _phones, _both, {LayoutDefect.primaryActionBelowFold},
      'Create comes after the hero and three field cards'),
  KnownPhoneLayoutFailure('chat-room-warnings-keyboard-larger-text', _small, _both, {LayoutDefect.hiddenAction},
      'at 360x640 with the keyboard, two warnings and 1.3x text the second warning row is cut off'),
  KnownPhoneLayoutFailure('wide-chat', [wideSmall], _both,
      {LayoutDefect.overflow, LayoutDefect.primaryContentSqueezed},
      'the second pane stacks a hero, a header card, a search card and tiles above the messages and overflows'),
  KnownPhoneLayoutFailure('wide-chat', [wideLarge], _both, {LayoutDefect.primaryContentSqueezed},
      'the second pane stacks a hero, a header card, a search card and tiles above the messages'),
  KnownPhoneLayoutFailure('wide-chat-warnings', [wideSmall], _both,
      {LayoutDefect.overflow, LayoutDefect.primaryContentSqueezed, LayoutDefect.hiddenAction},
      'with two warnings under the cards the second pane overflows, the messages get no height, and '
          'both warning actions (Review, Retry failed sends) are pushed below the screen'),
  KnownPhoneLayoutFailure(
      'wide-chat-warnings',
      [wideLarge],
      _both,
      {
        LayoutDefect.overflow,
        LayoutDefect.primaryContentSqueezed,
        LayoutDefect.hiddenAction,
        LayoutDefect.smallTapTarget,
      },
      'with two warnings under the cards the second pane overflows, the messages get no height, and '
          'Retry failed sends is cut to a 9 px strip under the composer'),

  // --- Settings, security status, safety numbers, contacts, one-time link.
  KnownPhoneLayoutFailure('settings', _phones, _both, {LayoutDefect.primaryActionBelowFold},
      'the first setting (the theme, then the privacy switches) comes after the hero, the profile row and the device list'),
  KnownPhoneLayoutFailure('contacts', [phoneSmall, phoneMedium], _both, {LayoutDefect.primaryContentSqueezed},
      'the notice and the add button above the list leave the contacts a quarter to a third of the screen'),

  // --- Switched-off surfaces (calls, media, voice, stickers, assistant,
  // stories, attachments): fixed by whoever switches one on.
];

KnownPhoneLayoutFailure? knownPhoneLayoutFailure(String caseId, PhoneSize size, String locale, {bool light = false}) {
  for (final known in knownPhoneLayoutFailures) {
    if (known.caseId == caseId &&
        known.light == light &&
        known.sizes.contains(size) &&
        known.locales.contains(locale)) {
      return known;
    }
  }
  return null;
}
