// The handles an honest server issues, and how one it could not have issued
// is shown.
//
// The server registers a handle only in this grammar (apps/api
// src/modules/auth/dto/register.dto.ts, which __tests__/handles.test.js
// reads to keep the two equal): 3 to 32 characters of a-z, 0-9, '.' and
// '_', starting and ending with a letter or digit, with no two separators
// in a row. It exists to stop lookalikes. The conversation list is relayed,
// though, and a hostile relay can list any account under any string: 'bob'
// with a zero-width space after it, with a Cyrillic 'o' (U+043E), with a
// trailing space or a right-to-left override in front. Each renders as
// 'bob' and none equals it, so a check against the handles this device
// knows misses it. A listed handle outside the grammar came from no honest
// server, and a direct conversation listed under one admits nothing until
// the user chooses to talk to that account (src/domain/peer-bindings.js
// hold).

export const HANDLE_MIN_LENGTH = 3;
export const HANDLE_MAX_LENGTH = 32;
export const ISSUED_HANDLE_PATTERN = /^[a-z0-9](?!.*[._]{2})[a-z0-9._]*[a-z0-9]$/;

// Whether an honest server could have issued this handle.
export function isIssuableHandle(handle) {
  return (
    typeof handle === 'string' &&
    handle.length >= HANDLE_MIN_LENGTH &&
    handle.length <= HANDLE_MAX_LENGTH &&
    ISSUED_HANDLE_PATTERN.test(handle)
  );
}

const ISSUABLE_CHARACTER = /^[a-z0-9._]$/;

const codePoint = (character) => `[U+${character.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')}]`;

// The handle as the conversation list, the panel header, banners and
// notifications show it: as it is when an honest server could have issued
// it; otherwise with every character no handle can hold written as its code
// point ('bob' and a zero-width space as 'bob[U+200B]', 'bob' with a
// Cyrillic 'o' as 'b[U+043E]b'), so it never renders like one that could.
// Every view names a handle through this once, from the handle as listed;
// '?' is what the views write for no handle, and stays as it is.
export function shownHandle(handle) {
  if (typeof handle !== 'string' || handle === '' || handle === '?') return '?';
  if (isIssuableHandle(handle)) return handle;
  let shown = '';
  for (const character of handle) shown += ISSUABLE_CHARACTER.test(character) ? character : codePoint(character);
  return shown;
}
