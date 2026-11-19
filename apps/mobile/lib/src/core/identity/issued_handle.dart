// The handles an honest relay issues: 3 to 32 characters of a-z, 0-9, '.'
// and '_', starting and ending with a letter or digit, with no two
// separators in a row (apps/api RegisterDto; test/identity/issued_handle_test
// reads it to keep the two equal). The conversation list is relayed, though,
// and a hostile relay can list any account under any string: 'bob' with a
// zero-width space after it, or with a Cyrillic 'o'. Each renders as 'bob'
// and none equals it, so a check against the handles this device knows
// misses it. A handle outside the grammar came from no honest relay.

const issuedHandleMinLength = 3;
const issuedHandleMaxLength = 32;
final issuedHandlePattern = RegExp(r'^[a-z0-9](?!.*[._]{2})[a-z0-9._]*[a-z0-9]$');

/// Only characters an issued handle can hold, in any number.
final issuableHandleCharacters = RegExp(r'^[a-z0-9._]*$');

/// Whether an honest relay could have issued [handle].
bool isIssuableHandle(String handle) =>
    handle.length >= issuedHandleMinLength &&
    handle.length <= issuedHandleMaxLength &&
    issuedHandlePattern.hasMatch(handle);

/// The rules of that grammar, one at a time, so Choose a handle can say
/// which one a typed handle breaks, as Signal's username screen does (and
/// the web app's sign-in, src/domain/handles.js HandleRule).
enum HandleRule {
  /// 3 to 32 characters of a-z, 0-9, '.' and '_'.
  characters,

  /// Starts and ends with a letter or digit.
  edges,

  /// No two separators in a row.
  run,
}

final _letterOrDigitAtBothEnds = RegExp(r'^[a-z0-9](.*[a-z0-9])?$');
final _separatorRun = RegExp(r'[._]{2}');

/// The first rule [handle] breaks, or null when the relay registers it:
/// null exactly when [isIssuableHandle] holds. The same order as the web
/// app's handleRuleBroken.
HandleRule? handleRuleBroken(String handle) {
  if (handle.length < issuedHandleMinLength || handle.length > issuedHandleMaxLength) return HandleRule.characters;
  if (!issuableHandleCharacters.hasMatch(handle)) return HandleRule.characters;
  if (!_letterOrDigitAtBothEnds.hasMatch(handle)) return HandleRule.edges;
  if (_separatorRun.hasMatch(handle)) return HandleRule.run;
  return null;
}
