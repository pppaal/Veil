import 'support/phone_layout_probe.dart';

// The allow-list of the phone layout gate (phone_layout_test.dart).

/// A case that is known not to fit a phone, and how it fails.
class KnownPhoneLayoutFailure {
  const KnownPhoneLayoutFailure(this.caseId, this.size, this.locale, this.defects, this.reason);

  /// A ScreenCase id from support/screen_cases.dart.
  final String caseId;
  final PhoneSize size;
  final String locale;

  /// Exactly the defects the case shows today.
  final Set<LayoutDefect> defects;
  final String reason;
}

/// Screens that do not fit a phone. The gate fails for any failing case that
/// is not listed here, and for any listed case that passes or fails in
/// another way than listed, so this list can only shrink.
///
/// It is empty: every case fits. Keep it empty by fixing the layout; a line
/// here is only for a defect that has to ship before its fix, with the
/// reason it has to.
const knownPhoneLayoutFailures = <KnownPhoneLayoutFailure>[];

KnownPhoneLayoutFailure? knownPhoneLayoutFailure(String caseId, PhoneSize size, String locale) {
  for (final known in knownPhoneLayoutFailures) {
    if (known.caseId == caseId && known.size == size && known.locale == locale) return known;
  }
  return null;
}
