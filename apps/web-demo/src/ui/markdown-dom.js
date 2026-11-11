// Message markdown, rendered without ever parsing HTML.
//
// tokenize() is a single left-to-right pass: code fences first, then inline
// code, http(s) URLs, @mentions and *strong* / _em_ emphasis. Code, URLs and
// mentions are opaque to emphasis, so an asterisk or underscore inside them
// never splits them. The token tree is turned into DOM with createElement /
// textContent (toFragment) or into an escaped string for node tests
// (toHtmlString). Both renderers share one element description, so the only
// tags that can appear are a, code, pre, strong, em and span.mention.

const FENCE = '```';
const FENCE_LANG_RE = /[A-Za-z0-9_+-]*/y;
const URL_RE = /https?:\/\/[^\s<>()`]+/y;
// GFM autolink rule: trailing punctuation is not part of the link.
const URL_TRAILING_PUNCTUATION_RE = /[?!.,:*_~]+$/;
const HANDLE_RE = /[a-z0-9_]+/y;
const MIN_HANDLE = 3;
const MAX_HANDLE = 32;
const WORD_CHAR_RE = /[A-Za-z0-9_]/;
const MENTION_BOUNDARY_RE = /[\s(\[{,.;:!?]/;
const EM_BOUNDARY_RE = /[\s(\[]/;

const LINK_ATTRIBUTES = Object.freeze([
  ['target', '_blank'],
  ['rel', 'noopener noreferrer'],
  ['referrerpolicy', 'no-referrer'],
]);

export function tokenize(text) {
  const source = String(text ?? '');
  const nodes = [];
  let segmentStart = 0;
  let searchFrom = 0;
  while (searchFrom < source.length) {
    const open = source.indexOf(FENCE, searchFrom);
    if (open === -1) break;
    const fence = matchFence(source, open);
    // No closing fence after this opener means none after any later one.
    if (fence === null) break;
    nodes.push(...parseInline(source.slice(segmentStart, open)), fence.node);
    segmentStart = searchFrom = fence.end;
  }
  nodes.push(...parseInline(source.slice(segmentStart)));
  return nodes;
}

export function toFragment(text, doc = globalThis.document) {
  const fragment = doc.createDocumentFragment();
  for (const node of tokenize(text)) fragment.appendChild(buildDom(node, doc));
  return fragment;
}

export function toHtmlString(text) {
  return tokenize(text).map(buildHtml).join('');
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function matchFence(source, open) {
  const afterOpen = open + FENCE.length;
  FENCE_LANG_RE.lastIndex = afterOpen;
  const info = FENCE_LANG_RE.exec(source)[0];
  // A language tag needs the opening line to itself; in "```word```" the
  // word is the code.
  const ownLine = source[afterOpen + info.length] === '\n';
  const lang = ownLine ? info : '';
  const bodyStart = ownLine ? afterOpen + info.length + 1 : afterOpen;
  const close = source.indexOf(FENCE, bodyStart);
  if (close === -1) return null;
  const body = source.slice(bodyStart, close).replace(/\n$/, '');
  return { node: { type: 'pre', lang, text: body }, end: close + FENCE.length };
}

function parseInline(text) {
  const nodes = [];
  let plainStart = 0;
  let i = 0;
  while (i < text.length) {
    const token = matchInlineAt(text, i);
    if (token === null) {
      i += 1;
      continue;
    }
    if (i > plainStart) nodes.push({ type: 'text', text: text.slice(plainStart, i) });
    nodes.push(token.node);
    i = plainStart = token.end;
  }
  if (plainStart < text.length) nodes.push({ type: 'text', text: text.slice(plainStart) });
  return nodes;
}

function matchInlineAt(text, i) {
  switch (text[i]) {
    case '*':
      return matchEmphasis(text, i, '*', 'strong');
    case '_':
      return matchEmphasis(text, i, '_', 'em');
    default:
      return matchOpaqueAt(text, i);
  }
}

// Tokens whose content emphasis delimiters cannot cut through.
function matchOpaqueAt(text, i) {
  switch (text[i]) {
    case '`':
      return matchCode(text, i);
    case 'h':
      return matchUrl(text, i);
    case '@':
      return matchMention(text, i);
    default:
      return null;
  }
}

function matchCode(text, i) {
  const close = text.indexOf('`', i + 1);
  if (close === -1) return null;
  const body = text.slice(i + 1, close);
  if (body.length === 0 || body.includes('\n')) return null;
  return { node: { type: 'code', text: body }, end: close + 1 };
}

function matchUrl(text, i) {
  if (i > 0 && WORD_CHAR_RE.test(text[i - 1])) return null;
  URL_RE.lastIndex = i;
  const match = URL_RE.exec(text);
  if (match === null) return null;
  const candidate = match[0].replace(URL_TRAILING_PUNCTUATION_RE, '');
  const href = safeHttpHref(candidate);
  if (href === null) return null;
  return { node: { type: 'link', href, text: candidate }, end: i + candidate.length };
}

function matchMention(text, i) {
  if (i > 0 && !MENTION_BOUNDARY_RE.test(text[i - 1])) return null;
  HANDLE_RE.lastIndex = i + 1;
  const match = HANDLE_RE.exec(text);
  if (match === null) return null;
  const handle = match[0];
  const end = i + 1 + handle.length;
  if (handle.length < MIN_HANDLE || handle.length > MAX_HANDLE) return null;
  if (end < text.length && WORD_CHAR_RE.test(text[end])) return null;
  return { node: { type: 'mention', handle }, end };
}

function matchEmphasis(text, i, delimiter, type) {
  if (delimiter === '_' && i > 0 && !EM_BOUNDARY_RE.test(text[i - 1])) return null;
  let j = i + 1;
  while (j < text.length && text[j] !== delimiter) {
    if (text[j] === '\n') return null;
    j = matchOpaqueAt(text, j)?.end ?? j + 1;
  }
  if (j >= text.length || j === i + 1) return null;
  return { node: { type, children: parseInline(text.slice(i + 1, j)) }, end: j + 1 };
}

function safeHttpHref(candidate) {
  let url;
  try {
    url = new URL(candidate);
  } catch {
    return null;
  }
  return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : null;
}

function describe(node) {
  switch (node.type) {
    case 'code':
      return { tag: 'code', attributes: [], children: [{ type: 'text', text: node.text }] };
    case 'pre':
      return {
        tag: 'pre',
        attributes: node.lang ? [['class', 'msg-codeblock'], ['data-lang', node.lang]] : [['class', 'msg-codeblock']],
        children: [{ type: 'code', text: node.text }],
      };
    case 'link':
      return { tag: 'a', attributes: [['href', node.href], ...LINK_ATTRIBUTES], children: [{ type: 'text', text: node.text }] };
    case 'mention':
      return { tag: 'span', attributes: [['class', 'mention']], children: [{ type: 'text', text: `@${node.handle}` }] };
    default:
      return { tag: node.type, attributes: [], children: node.children };
  }
}

function buildDom(node, doc) {
  if (node.type === 'text') return doc.createTextNode(node.text);
  const { tag, attributes, children } = describe(node);
  const element = doc.createElement(tag);
  for (const [name, value] of attributes) element.setAttribute(name, value);
  for (const child of children) element.appendChild(buildDom(child, doc));
  return element;
}

function buildHtml(node) {
  if (node.type === 'text') return escapeHtml(node.text);
  const { tag, attributes, children } = describe(node);
  const attributeText = attributes.map(([name, value]) => ` ${name}="${escapeHtml(value)}"`).join('');
  return `<${tag}${attributeText}>${children.map(buildHtml).join('')}</${tag}>`;
}
