// VEIL web demo client: the bootstrap. It builds the state store, the
// services and the views, wires them to each other and to the page, and
// signs the stored identity back in. docs/web-architecture.md maps the
// modules and the rules between them.
//
// The client talks to the NestJS API at /v1 and the realtime gateway at
// /v1/realtime. Messages are end-to-end encrypted with protocol v2
// ('veil-envelope-v2', docs/crypto-envelope-spec.md): X3DH with signed and
// one-time prekeys, then a Double Ratchet, byte-compatible with the mobile
// client (src/crypto/). Each ciphertext is decrypted once into an encrypted
// local store, which is all rendering reads. The server only ever sees
// ciphertext.

import { initI18n, t } from './i18n/i18n.js';
import { createMessagingStack } from './src/app/messaging-stack.js';
import { createAttachments } from './src/app/services/attachments.js';
import { createDeviceTransfer } from './src/app/services/device-transfer.js';
import { createHistorySync } from './src/app/services/history-sync.js';
import { createIdentityTrust } from './src/app/services/identity-trust.js';
import { createInbound } from './src/app/services/inbound.js';
import { createKakaoArchives } from './src/app/services/kakao-archives.js';
import { createMessages } from './src/app/services/messages.js';
import { createNotifications } from './src/app/services/notifications.js';
import { createOutbox } from './src/app/services/outbox.js';
import { createPreferences } from './src/app/services/preferences.js';
import { createRealtime } from './src/app/services/realtime.js';
import { createSafety } from './src/app/services/safety.js';
import { createSend } from './src/app/services/send.js';
import { createSession } from './src/app/services/session.js';
import { createStore } from './src/app/store.js';
import { createConfirm } from './src/ui/confirm.js';
import { createDialogs } from './src/ui/dialogs.js';
import { createSounds } from './src/ui/sounds.js';
import { toast } from './src/ui/toast.js';
import { createAppShell } from './src/ui/views/app-shell.js';
import { createAuthView } from './src/ui/views/auth-view.js';
import { createChatView } from './src/ui/views/chat-view.js';
import { createComposer } from './src/ui/views/composer.js';
import { createForwardDialog } from './src/ui/views/forward-dialog.js';
import { createHelpDialog } from './src/ui/views/help-dialog.js';
import { createKakaoImport } from './src/ui/views/kakao-import.js';
import { createKeyChangeBanner } from './src/ui/views/key-change-banner.js';
import { createMentions } from './src/ui/views/mentions.js';
import { copyHandle, createMenu, showConnectionStatus } from './src/ui/views/menu.js';
import { createMessageActions } from './src/ui/views/message-actions.js';
import { createMessageList } from './src/ui/views/message-list.js';
import { createNewChatDialog } from './src/ui/views/new-chat-dialog.js';
import { createNotificationPrompt } from './src/ui/views/notification-prompt.js';
import { createPanelSearch } from './src/ui/views/panel-search.js';
import { createReportDialog } from './src/ui/views/report-dialog.js';
import { createSafetyDialog } from './src/ui/views/safety-dialog.js';
import { createSettingsDialog } from './src/ui/views/settings-dialog.js';
import { createShortcuts } from './src/ui/views/shortcuts.js';
import { createSidebar } from './src/ui/views/sidebar.js';
import { createTabs } from './src/ui/views/tabs.js';
import { createTransferDialogs } from './src/ui/views/transfer-dialogs.js';
import { createVoiceRecorder } from './src/ui/views/voice-recorder.js';

// Translations load before anything renders, so the static strings in the
// page are rewritten before the user sees them.
await initI18n();

const preferences = createPreferences();
const store = createStore({ mutedConversations: preferences.mutedConversations(), soundsEnabled: preferences.soundsEnabled() });
const dialogs = createDialogs(document);
const confirm = createConfirm(dialogs);
const shell = createAppShell({ store, preferences });
shell.applyTheme();

// The stack's hooks reach services built below; none fires before the
// stored identity is loaded at the very end.
const stack = createMessagingStack({
  store,
  hooks: {
    onStorageBlocked: () => toast(t('storage.upgradeBlocked'), 'error'),
    // Another tab wiped this browser's VEIL data. Reloading drops everything
    // this tab still holds in memory and boots from the now-empty storage.
    onDeletedElsewhere: () => location.reload(),
    // Once the user approved a device transfer, the server revoking this
    // device is how the transfer's completion arrives here, and the transfer
    // watch then destroys the spent identity.
    onSessionRejected: async () => {
      if ((await transfer.sessionEnded()) === 'completed') return;
      await session.end({ rejected: true });
    },
    onTokensSaved: () => realtime.reviveIfDisconnected(),
    onTrustChange: () => store.notify('sidebar', 'panels'),
  },
});

// Services: what the app does, with no knowledge of the page.
const messages = createMessages({ store, stack });
const outbox = createOutbox({ store, stack, messages, toast });
const history = createHistorySync({ store, stack, messages, outbox, toast, isRealtimeConnected: () => realtime.isConnected() });
const notifications = createNotifications({ store, preferences, peerOf: stack.peerOf });
const inbound = createInbound({ store, messages, history, notifications });
const sounds = createSounds({ isEnabled: () => store.state.soundsEnabled });
const realtime = createRealtime({
  store,
  stack,
  history,
  outbox,
  inbound,
  messages,
  getIo: () => window.io,
  onStatus: shell.setConnection,
  onRetry: shell.setRetry,
  onPeerMessage: sounds.playReceive,
});
const send = createSend({ store, stack, messages, realtime, onSent: sounds.playSend, toast });
const attachments = createAttachments({ store, stack, messages, send });
const identityTrust = createIdentityTrust({ store, stack, messages });
const safety = createSafety({ store, stack, preferences, toast });
const archives = createKakaoArchives({ store, stack });
const session = createSession({
  store,
  stack,
  messages,
  history,
  realtime,
  archives,
  ui: { showApp: shell.show, showAuth: (options) => auth.show(options), toast },
});
const transfer = createDeviceTransfer({ store, stack, session });

// Views: what the user sees and does.
const tabs = createTabs({ store, history });
const kakao = createKakaoImport({ store, archives });
const sidebar = createSidebar({ store, stack, navigation: tabs, archiveRows: kakao.rows });
const voice = createVoiceRecorder({ attachments });
const composer = createComposer({ store, send, attachments, realtime, voice, sounds });
const messageList = createMessageList({ store, send, outbox, startReply: composer.startReply });
const safetyDialog = createSafetyDialog({ identityTrust, dialogs });
const keyChangeBanner = createKeyChangeBanner({ identityTrust, safetyDialog, confirm });
const panelSearch = createPanelSearch({ store });
const chat = createChatView({ store, stack, messages, messageList, composer, keyChangeBanner, safetyDialog, panelSearch, safety, confirm });
const forwardDialog = createForwardDialog({ store, composer });
const reportDialog = createReportDialog({ safety, dialogs });
const messageActions = createMessageActions({ store, send, safety, composer, forwardDialog, reportDialog, confirm });
const auth = createAuthView({ stack, session, confirm });
const transferDialogs = createTransferDialogs({ store, transfer, session, auth, dialogs, confirm });
const settings = createSettingsDialog({ store, preferences, safety });
const help = createHelpDialog({ store });

store.subscribe('sidebar', sidebar.render);
store.subscribe('panels', chat.render);
store.subscribe('tabs', tabs.render);
store.subscribe('session-reset', () => {
  transferDialogs.stopOld();
  chat.forgetReads();
  shell.reset();
});

createMenu({
  actions: {
    'copy-handle': () => copyHandle(store.state.me.handle),
    'ws-info': () => showConnectionStatus(realtime.isConnected(), history.POLL_MS),
    'transfer-start': () => transferDialogs.startOld(),
    wipe: () => auth.confirmAndDestroyIdentity(),
    'toggle-sounds': () => settings.toggleSounds(),
    'show-help': () => help.open(),
    'open-settings': () => settings.open(),
    'kakao-import': () => kakao.openDialog(),
  },
}).mount();
messageActions.mount();
sounds.mount();
createShortcuts({ openHelp: help.open, toggleSounds: settings.toggleSounds }).mount();
panelSearch.mount();
createMentions({ store }).mount();
composer.mount();
createNotificationPrompt({ store, preferences }).mount();
auth.mount();
sidebar.mount();
createNewChatDialog({ store, stack, history, tabs, dialogs }).mount();
tabs.mount();
shell.mountBetaBanner();
transferDialogs.mount();

auth.boot();
