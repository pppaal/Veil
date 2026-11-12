// In-conversation search over what the panel shows.

import { isShown, isTextKind } from './ingest.js';

// The shown text messages whose text contains `query`, case-insensitively.
export function searchMatches(messages, query, now = Date.now()) {
  const wanted = query.trim().toLowerCase();
  if (!wanted) return [];
  return messages.filter((message) =>
    isShown(message, now) && isTextKind(message.kind) && message.displayText.toLowerCase().includes(wanted));
}

// `text` cut into [{ text, match }] runs around every occurrence of `query`.
export function highlightRuns(text, query) {
  const lower = text.toLowerCase();
  const wanted = query.toLowerCase();
  const runs = [];
  let cursor = 0;
  while (cursor < text.length) {
    const found = lower.indexOf(wanted, cursor);
    if (found === -1) {
      runs.push({ text: text.slice(cursor), match: false });
      break;
    }
    if (found > cursor) runs.push({ text: text.slice(cursor, found), match: false });
    runs.push({ text: text.slice(found, found + query.length), match: true });
    cursor = found + query.length;
  }
  return runs;
}

// The position after `index` among `total` matches, stepping back with
// `backwards`, wrapping at both ends.
export const stepMatch = (index, total, backwards = false) =>
  backwards ? (index - 1 + total) % total : (index + 1) % total;
