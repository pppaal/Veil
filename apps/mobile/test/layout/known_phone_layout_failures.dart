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
  KnownPhoneLayoutFailure('privacy-consent', _phones, _both, {LayoutDefect.primaryActionBelowFold},
      'the agree control comes after three screenfuls of the notice'),
  KnownPhoneLayoutFailure('create-account', _small, _both, {LayoutDefect.primaryActionBelowFold},
      'at 360x640 Continue starts below the fold, under the hero and the field'),
  KnownPhoneLayoutFailure('device-transfer-new-device', [phoneSmall, phoneMedium], _both,
      {LayoutDefect.primaryActionBelowFold}, 'the first field comes after the hero, the mode chips and the notice'),
  KnownPhoneLayoutFailure('device-transfer-old-device', _phones, _both, {LayoutDefect.primaryActionBelowFold},
      'the claim field comes after the hero, the notice, the tiles and the transfer code'),

  // --- Chat and conversation list (phone and wide), starting a chat or a group.
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
