// The app's strings. English is the only language: i18n/en.json is the one
// dictionary, loaded before anything renders, with {placeholder}
// interpolation only and no build step. The browser's language, the URL and
// storage play no part.
let dict = {};

export async function initI18n() {
  const res = await fetch('./i18n/en.json');
  if (!res.ok) throw new Error('strings failed to load');
  dict = await res.json();
  document.documentElement.lang = 'en';
  document.documentElement.dir = 'ltr';
  applyDomTranslations();
}

export function t(key, vars) {
  const raw = dict[key] ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (_, name) =>
    Object.prototype.hasOwnProperty.call(vars, name) ? String(vars[name]) : `{${name}}`,
  );
}

// Strings may emphasise with <strong>…</strong> and break lines with <br>;
// nothing else in a string is ever parsed as markup.
const RICH_TOKEN_RE = /(<strong>|<\/strong>|<br\s*\/?>)/;
const BREAK_RE = /^<br\s*\/?>$/;

function richText(markup) {
  const fragment = document.createDocumentFragment();
  let target = fragment;
  for (const part of markup.split(RICH_TOKEN_RE)) {
    if (part === '<strong>') {
      target = fragment.appendChild(document.createElement('strong'));
    } else if (part === '</strong>') {
      target = fragment;
    } else if (BREAK_RE.test(part)) {
      target.appendChild(document.createElement('br'));
    } else if (part) {
      target.appendChild(document.createTextNode(part));
    }
  }
  return fragment;
}

// Walks the DOM once at init and fills in every element with a data-i18n
// attribute, so the static page and the dictionary say the same thing.
function applyDomTranslations() {
  for (const node of document.querySelectorAll('[data-i18n]')) {
    const key = node.getAttribute('data-i18n');
    if (key) node.textContent = t(key);
  }
  for (const node of document.querySelectorAll('[data-i18n-html]')) {
    const key = node.getAttribute('data-i18n-html');
    if (key) node.replaceChildren(richText(t(key)));
  }
  for (const node of document.querySelectorAll('[data-i18n-placeholder]')) {
    const key = node.getAttribute('data-i18n-placeholder');
    if (key) node.placeholder = t(key);
  }
  for (const node of document.querySelectorAll('[data-i18n-aria-label]')) {
    const key = node.getAttribute('data-i18n-aria-label');
    if (key) node.setAttribute('aria-label', t(key));
  }
}
