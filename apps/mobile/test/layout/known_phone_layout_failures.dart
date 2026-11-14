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

const _overflows = {LayoutDefect.overflow};
const _squeezed = {LayoutDefect.primaryContentSqueezed};
const _overflowsAndSqueezed = {LayoutDefect.overflow, LayoutDefect.primaryContentSqueezed};

const _lockHeader = 'the PIN block puts its label and three status pills on one row, which is wider than the card';
const _listHeader = 'a hero card, three stat tiles and a search card come before the first conversation';
const _chatHeader = 'a hero card, an info card, a search card and four stat tiles are fixed above the messages, '
    'which get no height while the column overflows the screen';
const _chatHeaderNoOverflow = 'a hero card, an info card, a search card and four stat tiles are fixed above the '
    'messages; the column just fits here, with nothing left for the messages';

/// Screens that do not fit a phone today. The gate fails for any failing
/// case that is not listed here, and for any listed case that passes or
/// fails in another way than listed, so this list can only shrink. It is to
/// be emptied, never extended: fix the layout instead of adding a line.
const knownPhoneLayoutFailures = <KnownPhoneLayoutFailure>[
  KnownPhoneLayoutFailure('app-lock', phoneSmall, 'en', _overflows, _lockHeader),
  KnownPhoneLayoutFailure('app-lock', phoneSmall, 'ko', _overflows, _lockHeader),
  KnownPhoneLayoutFailure('app-lock', phoneMedium, 'en', _overflows, _lockHeader),
  KnownPhoneLayoutFailure('app-lock', phoneMedium, 'ko', _overflows, _lockHeader),
  KnownPhoneLayoutFailure('app-lock', phoneLarge, 'en', _overflows, _lockHeader),
  KnownPhoneLayoutFailure('app-lock', phoneLarge, 'ko', _overflows, _lockHeader),

  KnownPhoneLayoutFailure('conversation-list', phoneSmall, 'en', _squeezed, _listHeader),
  KnownPhoneLayoutFailure('conversation-list', phoneSmall, 'ko', _squeezed, _listHeader),
  KnownPhoneLayoutFailure('conversation-list', phoneMedium, 'en', _squeezed, _listHeader),
  KnownPhoneLayoutFailure('conversation-list', phoneMedium, 'ko', _squeezed, _listHeader),
  KnownPhoneLayoutFailure('conversation-list', phoneLarge, 'en', _squeezed, _listHeader),
  KnownPhoneLayoutFailure('conversation-list', phoneLarge, 'ko', _squeezed, _listHeader),

  KnownPhoneLayoutFailure('chat-room', phoneSmall, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room', phoneSmall, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room', phoneMedium, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room', phoneMedium, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room', phoneLarge, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room', phoneLarge, 'ko', _overflowsAndSqueezed, _chatHeader),

  KnownPhoneLayoutFailure('chat-room-empty', phoneSmall, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-empty', phoneSmall, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-empty', phoneMedium, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-empty', phoneMedium, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-empty', phoneLarge, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-empty', phoneLarge, 'ko', _squeezed, _chatHeaderNoOverflow),

  KnownPhoneLayoutFailure('chat-room-keyboard', phoneSmall, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-keyboard', phoneSmall, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-keyboard', phoneMedium, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-keyboard', phoneMedium, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-keyboard', phoneLarge, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-keyboard', phoneLarge, 'ko', _overflowsAndSqueezed, _chatHeader),

  KnownPhoneLayoutFailure('chat-room-warnings', phoneSmall, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-warnings', phoneSmall, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-warnings', phoneMedium, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-warnings', phoneMedium, 'ko', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-warnings', phoneLarge, 'en', _overflowsAndSqueezed, _chatHeader),
  KnownPhoneLayoutFailure('chat-room-warnings', phoneLarge, 'ko', _overflowsAndSqueezed, _chatHeader),
];

KnownPhoneLayoutFailure? knownPhoneLayoutFailure(String caseId, PhoneSize size, String locale) {
  for (final known in knownPhoneLayoutFailures) {
    if (known.caseId == caseId && known.size == size && known.locale == locale) return known;
  }
  return null;
}
