// Keyboard shortcuts as the user's platform writes them: ⌘ on a Mac, Ctrl
// everywhere else, never "Ctrl/Cmd".

import { t } from '../../i18n/i18n.js';

export const isMac = () => /Mac|iPhone|iPad/.test(navigator.userAgentData?.platform ?? navigator.platform ?? '');

// The modifier key's name: "⌘" or "Ctrl".
export const modifierKey = () => t(isMac() ? 'help.keyMac' : 'help.keyOther');

// A shortcut for a tooltip: "⌘N" on a Mac, "Ctrl+N" elsewhere.
export const shortcutLabel = (key) => (isMac() ? `${modifierKey()}${key}` : `${modifierKey()}+${key}`);
