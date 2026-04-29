// Tiny i18n loader. Honors ?lang= query param first, then navigator.language,
// then falls back to ko. Translations are static JSON files we ship in
// /i18n/{lang}.json — no build step. {placeholder} interpolation only.
const SUPPORTED = new Set(['ko', 'en', 'ja']);
const FALLBACK = 'ko';

let dict = {};
let active = FALLBACK;

function pickLang() {
  try {
    const q = new URLSearchParams(location.search).get('lang');
    if (q && SUPPORTED.has(q)) return q;
  } catch {}
  try {
    const stored = localStorage.getItem('veil-demo-lang');
    if (stored && SUPPORTED.has(stored)) return stored;
  } catch {}
  const nav = (navigator.language || '').slice(0, 2).toLowerCase();
  if (SUPPORTED.has(nav)) return nav;
  return FALLBACK;
}

export async function initI18n() {
  active = pickLang();
  try {
    const res = await fetch(`./i18n/${active}.json`);
    if (!res.ok) throw new Error('lang load failed');
    dict = await res.json();
  } catch {
    if (active !== FALLBACK) {
      const res = await fetch(`./i18n/${FALLBACK}.json`);
      dict = await res.json();
      active = FALLBACK;
    }
  }
  document.documentElement.lang = active;
  // RTL prep: Arabic and Hebrew (not yet shipped) would flip dir here.
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

export function setLang(lang) {
  if (!SUPPORTED.has(lang)) return;
  try { localStorage.setItem('veil-demo-lang', lang); } catch {}
  location.reload();
}

export function activeLang() {
  return active;
}

// Walks the DOM once at init and replaces text/HTML for any element with
// a data-i18n attribute. Keeps existing static strings working without
// touching every render path immediately — Phase AA can grow into the
// codebase incrementally.
function applyDomTranslations() {
  for (const node of document.querySelectorAll('[data-i18n]')) {
    const key = node.getAttribute('data-i18n');
    if (key) node.textContent = t(key);
  }
  for (const node of document.querySelectorAll('[data-i18n-html]')) {
    const key = node.getAttribute('data-i18n-html');
    if (key) node.innerHTML = t(key);
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
