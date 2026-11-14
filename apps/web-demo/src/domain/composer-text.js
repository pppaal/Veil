// Text rules of the composer and the forms around it.

// Cap a single message body. UTF-8 worst case is ~3 bytes/char so 8000 chars
// keeps us comfortably under the API's 64 KB envelope ceiling and prevents a
// 10 MB paste from locking the encrypt/render path.
export const MESSAGE_MAX_CHARS = 8000;

const HANDLE_RE = /^[a-z0-9_]{1,32}$/;

// Handles are lowercase; what a user types is trimmed and lowered first.
export const normalizeHandle = (typed) => typed.trim().toLowerCase();
export const isValidHandle = (handle) => HANDLE_RE.test(handle);

// The "@prefix" being typed at the caret: { start, prefix } when the caret
// sits right after an '@' word that starts the input or follows whitespace
// or punctuation, else null.
export function mentionAt(value, caret = value.length) {
  const left = value.slice(0, caret);
  const at = left.lastIndexOf('@');
  if (at < 0) return null;
  if (/\s/.test(left.slice(at + 1))) return null;
  const before = at > 0 ? left[at - 1] : ' ';
  if (!/\s|[(\[{,.;:!?]/.test(before)) return null;
  return { start: at, prefix: left.slice(at + 1) };
}

// Up to six members other than us whose handle starts with the prefix.
export function mentionCandidates(members, selfUserId, prefix) {
  const wanted = prefix.toLowerCase();
  return members
    .filter((member) => member.userId !== selfUserId)
    .filter((member) => (member.handle || '').toLowerCase().startsWith(wanted))
    .slice(0, 6);
}

// The composer text with the mention at `mention` completed to `handle`,
// and where the caret goes.
export function completeMention(value, caret, mention, handle) {
  return {
    value: value.slice(0, mention.start) + '@' + handle + ' ' + value.slice(caret),
    caret: mention.start + handle.length + 2,
  };
}
