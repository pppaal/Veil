// DOM building blocks every view uses. Everything is built with
// createElement and text nodes: no HTML string ever reaches the page.

import { shownHandle } from '../domain/handles.js';

export const $ = (id) => document.getElementById(id);

// Whether the page is in the one-column layout app.css switches to at phone
// width (its max-width: 720px block).
const NARROW_LAYOUT = '(max-width: 720px)';
export const isNarrowLayout = () => Boolean(window.matchMedia && window.matchMedia(NARROW_LAYOUT).matches);

// el('div', { class, dataset, onclick, ...attributes }, children)
export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === 'class') node.className = value;
    else if (key === 'dataset') Object.assign(node.dataset, value);
    else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
    else if (value != null) node.setAttribute(key, value);
  }
  for (const child of [].concat(children)) {
    if (child == null) continue;
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

const SVG_NS = 'http://www.w3.org/2000/svg';

// One icon of the sprite at the top of index.html (<symbol id="i-name">),
// drawn in currentColor; app.css sizes .i at 20px.
export function icon(name, className = '') {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('class', className ? `i ${className}` : 'i');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  const use = document.createElementNS(SVG_NS, 'use');
  use.setAttribute('href', `#i-${name}`);
  svg.appendChild(use);
  return svg;
}

// A button that shows only an icon; `label` is its accessible name.
export const iconButton = (name, label, attrs = {}) =>
  el('button', { type: 'button', class: 'icon-btn', 'aria-label': label, title: label, ...attrs }, [icon(name)]);

// FNV-1a, 32 bits, over the UTF-8 bytes of `text`: the hash the mobile app
// uses for the same avatar (apps/mobile veil_avatar.dart veilFnv1a32), so a
// person has one colour everywhere.
export function fnv1a32(text) {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

const AVATAR_COLOURS = 8;
export const avatarIndex = (handle) => fnv1a32(shownHandle(handle)) % AVATAR_COLOURS;

// A flat disc in one of eight colours (.av-0 to .av-7 in app.css) with the
// handle's first letter in white. A handle no honest server issues is drawn
// from its shown form (src/domain/handles.js shownHandle), never like the
// handle it imitates. The row it sits in carries the name, so the disc is
// hidden from assistive technology.
export function avatarFor(handle, size = 'md') {
  const shown = shownHandle(handle);
  if (shown === '?') return el('div', { class: `avatar size-${size} avatar-neutral`, 'aria-hidden': 'true' }, [icon('user')]);
  const initial = [...shown][0].toUpperCase();
  return el('div', { class: `avatar size-${size} av-${fnv1a32(shown) % AVATAR_COLOURS}`, 'aria-hidden': 'true' }, [initial]);
}

// "@handle" for member and contact rows. Handles only: profile text is not
// something the server keeps.
export const handleLine = (handle) => el('div', { class: 'handle-line' }, ['@' + shownHandle(handle)]);

// Light or dark: the class app.css keys the light tokens on, and the colour
// the browser paints its own bar in.
export function applyThemeClass(light) {
  document.documentElement.classList.toggle('theme-light', light);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', light ? '#FFFFFF' : '#000000');
}
