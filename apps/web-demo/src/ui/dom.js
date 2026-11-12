// DOM building blocks every view uses. Everything is built with
// createElement and text nodes: no HTML string ever reaches the page.

import { shownHandle } from '../domain/handles.js';

export const $ = (id) => document.getElementById(id);

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

// Deterministic gradient and initial for an avatar, from a handle.
const PALETTE = [
  ['#6c8eff', '#b06cff'],
  ['#ff6c8e', '#ffb46c'],
  ['#4ade80', '#22d3ee'],
  ['#fbbf24', '#fb7185'],
  ['#a855f7', '#ec4899'],
  ['#06b6d4', '#3b82f6'],
  ['#f97316', '#eab308'],
  ['#10b981', '#14b8a6'],
];

function handleHash(handle) {
  let hash = 0;
  for (let i = 0; i < handle.length; i++) hash = (hash * 31 + handle.charCodeAt(i)) >>> 0;
  return hash;
}

// A handle no honest server issues is drawn from its shown form
// (src/domain/handles.js shownHandle), never like the handle it imitates.
export function avatarFor(handle, size = 'md') {
  const shown = shownHandle(handle);
  const initial = shown[0].toUpperCase();
  const [a, b] = PALETTE[handleHash(shown) % PALETTE.length];
  return el(
    'div',
    { class: `avatar size-${size}`, style: `background: linear-gradient(135deg, ${a} 0%, ${b} 100%)`, title: handle ? shown : '' },
    [initial],
  );
}

// "@handle" for member and contact rows. Handles only: profile text is not
// something the server keeps.
export const handleLine = (handle, handleStyle) => el('div', handleStyle ? { style: handleStyle } : {}, ['@' + shownHandle(handle)]);

// Shimmering placeholder rows for the conversation list while the first
// /conversations response is on its way.
export function convSkeletons(count) {
  return Array.from({ length: count }, () =>
    el('div', { class: 'conv-skeleton', 'aria-hidden': 'true' }, [
      el('div', { class: 'conv-skeleton-avatar' }),
      el('div', { class: 'conv-skeleton-text' }, [
        el('div', { class: 'conv-skeleton-line w-60' }),
        el('div', { class: 'conv-skeleton-line w-40' }),
      ]),
    ]));
}

const SVG_NS = 'http://www.w3.org/2000/svg';

function svgNode(tag, attributes) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, value);
  return node;
}

const dot = (cx, cy) => svgNode('circle', { cx: String(cx), cy, r: '1.5', fill: 'currentColor', stroke: 'none' });

// Inline empty-state illustrations, drawn in currentColor so they follow
// the theme: 'chat' (no conversation open) or anything else (no messages).
export function emptyStateSvg(kind) {
  const svg = svgNode('svg', {
    viewBox: '0 0 96 96',
    width: '96',
    height: '96',
    fill: 'none',
    stroke: 'currentColor',
    'stroke-width': '2',
    'stroke-linecap': 'round',
    'stroke-linejoin': 'round',
  });
  if (kind === 'chat') {
    svg.append(
      svgNode('rect', { x: '14', y: '20', width: '50', height: '34', rx: '8' }),
      svgNode('rect', { x: '34', y: '40', width: '50', height: '34', rx: '8', opacity: '0.6' }),
      ...[29, 39, 49].map((cx) => dot(cx, '37')),
    );
  } else {
    svg.append(
      svgNode('path', { d: 'M14 60 Q 28 48 42 60 T 70 60 T 82 60', opacity: '0.7' }),
      svgNode('path', {
        d: 'M22 18 H 74 A 8 8 0 0 1 82 26 V 42 A 8 8 0 0 1 74 50 H 42 L 32 60 V 50 H 22 A 8 8 0 0 1 14 42 V 26 A 8 8 0 0 1 22 18 Z',
      }),
      ...[32, 44, 56, 68].map((cx) => dot(cx, '34')),
    );
  }
  return el('div', { class: 'empty-svg' }, [svg]);
}
