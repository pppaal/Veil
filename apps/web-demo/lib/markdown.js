// Pure functions extracted from app.js so they can be unit-tested
// without spinning up a browser. The browser-side app.js imports
// from this module too — single source of truth.

const URL_RE = /\b(https?:\/\/[^\s<>()]+)/g;
const CODE_RE = /`([^`\n]+)`/g;
const BOLD_RE = /\*([^*\n]+)\*/g;
// Italic must be preceded by start-of-string, whitespace, or a small
// punct set so we don't grab the underscores inside identifiers.
const ITALIC_RE = /(^|[\s(\[])_([^_\n]+)_/g;
// Mention chip: matches the same handle shape the server validates on
// register (3-32 chars of [a-z0-9_]). Allowed leading boundary kept
// permissive enough to chip mentions inside parentheses/punct.
const MENTION_RE = /(^|[\s(\[{,.;:!?])@([a-z0-9_]{3,32})\b/g;

export function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Returns an HTML string. The caller is expected to set innerHTML.
// HTML escape happens FIRST so subsequent regex passes operate on
// already-safe text — the only HTML produced from here is what we
// inject ourselves.
export function renderMessageInline(text) {
  if (typeof text !== 'string') return '';
  const escaped = escapeHtml(text);
  return escaped
    .replace(CODE_RE, '<code>$1</code>')
    .replace(BOLD_RE, '<strong>$1</strong>')
    .replace(ITALIC_RE, '$1<em>$2</em>')
    .replace(URL_RE, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>')
    .replace(MENTION_RE, '$1<span class="mention">@$2</span>');
}
