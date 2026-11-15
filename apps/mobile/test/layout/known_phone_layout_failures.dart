import 'support/phone_layout_probe.dart';

// The allow-list of the layout gate (phone_layout_test.dart).

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
/// Every case fits today, so the list is empty, and the gate's test
/// 'nothing is listed as known to fail' keeps it so.
const knownPhoneLayoutFailures = <KnownPhoneLayoutFailure>[];

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
