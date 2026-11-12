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

/// Whether an honest relay could have issued [handle].
bool isIssuableHandle(String handle) =>
    handle.length >= issuedHandleMinLength &&
    handle.length <= issuedHandleMaxLength &&
    issuedHandlePattern.hasMatch(handle);
