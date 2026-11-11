import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { createDialogs } from '../src/ui/dialogs.js';

// Document double: elements by id with a class list and focus(). Dialogs
// start hidden, as in index.html.
function fakeDocument(ids) {
  const doc = { activeElement: null };
  const elements = new Map(ids.map((id) => {
    const classes = new Set(id.endsWith('-dialog') ? ['hidden'] : []);
    const element = {
      id,
      classList: {
        add: (name) => { classes.add(name); },
        remove: (name) => { classes.delete(name); },
        contains: (name) => classes.has(name),
      },
      focus: () => { doc.activeElement = element; },
    };
    return [id, element];
  }));
  doc.getElementById = (id) => elements.get(id) ?? null;
  doc.contains = (node) => [...elements.values()].includes(node);
  return doc;
}

const IDS = [
  'transfer-new-btn',
  'transfer-new-dialog',
  'transfer-new-token',
  'transfer-new-claim',
  'confirm-dialog',
  'confirm-cancel',
  'new-chat-btn',
  'new-chat-dialog',
];

describe('createDialogs', () => {
  beforeEach(() => { vi.stubGlobal('requestAnimationFrame', (callback) => callback()); });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('a confirmation over a dialog gives focus back to the control that asked, and that dialog to its opener', () => {
    const doc = fakeDocument(IDS);
    const byId = (id) => doc.getElementById(id);
    const dialogs = createDialogs(doc);
    byId('transfer-new-btn').focus();

    dialogs.open('transfer-new-dialog', 'transfer-new-token');
    byId('transfer-new-claim').focus();
    dialogs.open('confirm-dialog', 'confirm-cancel');
    expect(doc.activeElement).toBe(byId('confirm-cancel'));

    dialogs.close('confirm-dialog');
    expect(doc.activeElement).toBe(byId('transfer-new-claim'));
    expect(byId('transfer-new-dialog').classList.contains('hidden')).toBe(false);

    dialogs.close('transfer-new-dialog');
    expect(doc.activeElement).toBe(byId('transfer-new-btn'));
  });

  it('a dialog closed beneath another leaves focus in the one on top', () => {
    const doc = fakeDocument(IDS);
    const byId = (id) => doc.getElementById(id);
    const dialogs = createDialogs(doc);
    byId('transfer-new-btn').focus();
    dialogs.open('transfer-new-dialog', 'transfer-new-claim');
    dialogs.open('confirm-dialog', 'confirm-cancel');

    dialogs.close('transfer-new-dialog');

    expect(byId('transfer-new-dialog').classList.contains('hidden')).toBe(true);
    expect(doc.activeElement).toBe(byId('confirm-cancel'));
  });

  it('forgets a dialog that was hidden without close()', () => {
    const doc = fakeDocument(IDS);
    const byId = (id) => doc.getElementById(id);
    const dialogs = createDialogs(doc);
    byId('transfer-new-btn').focus();
    dialogs.open('transfer-new-dialog', 'transfer-new-token');
    // The global Escape handler hides the backdrop directly.
    byId('transfer-new-dialog').classList.add('hidden');
    byId('new-chat-btn').focus();
    dialogs.open('new-chat-dialog');
    dialogs.close('new-chat-dialog');
    expect(doc.activeElement).toBe(byId('new-chat-btn'));

    // A later close of the hidden dialog has no stale focus to restore.
    dialogs.close('transfer-new-dialog');
    expect(doc.activeElement).toBe(byId('new-chat-btn'));
  });
});

describe('dialog stacking (app.css)', () => {
  const css = readFileSync(new URL('../app.css', import.meta.url), 'utf8');
  const zIndex = (selector) => {
    const escaped = selector.replace(/[.#-]/g, '\\$&');
    const rule = new RegExp(`(?:^|\\n|\\})\\s*${escaped}\\s*\\{([^}]*)\\}`).exec(css);
    return Number(/z-index:\s*(\d+)/.exec(rule?.[1] ?? '')?.[1]);
  };

  it('keeps the confirmation above every other dialog, whatever their order in the page', () => {
    expect(zIndex('.dialog-backdrop')).toBeGreaterThan(0);
    expect(zIndex('#confirm-dialog')).toBeGreaterThan(zIndex('.dialog-backdrop'));
  });
});
