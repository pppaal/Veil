// The device-bound session's lifecycle. Three distinct exits, so that
// nothing but an explicit, confirmed user action (or a completed transfer)
// can destroy the device identity:
//   end()              tokens dropped, keys kept, the auth screen offers Retry
//   destroyIdentity()  confirmed wipe of everything this browser stored
//   reset()            the in-memory teardown both share
// There is no account recovery: a destroyed identity is gone for good.

import { t } from '../../../i18n/i18n.js';
import { generateIdentity, publishedKeys } from '../../crypto/identity.js';
import { wipeEverything, wipeInPlace } from '../../platform/wipe.js';
import { webStorage } from './preferences.js';

const IDENTITY_CHANNEL = 'veil-demo-identity';

// history: src/app/services/history-sync.js; realtime:
// src/app/services/realtime.js; archives: src/app/services/kakao-archives.js.
// ui: { showApp(), showAuth({ rejected }), toast(message, kind) }.
export function createSession({ store, stack, messages, history, realtime, archives, ui }) {
  const { state } = store;
  const { sessionStore, apiClient, idb } = stack;

  // A device transfer in another tab replaced the stored identity in place
  // (clearReplacedIdentity), which, unlike a wipe, leaves the database for
  // open tabs to keep writing to. Reloading drops the replaced identity this
  // tab holds in memory before a token update writes it back over the new one.
  let identityChannel = null;
  try {
    identityChannel = new BroadcastChannel(IDENTITY_CHANNEL);
  } catch {}
  identityChannel?.addEventListener('message', (event) => {
    if (event.data?.kind === 'identity-replaced') location.reload();
  });

  async function enterApp() {
    state.me = sessionStore.current();
    // Without them the app still works: a pending key change is raised again
    // by the next frame or lookup that presents it, and history is fetched
    // back from the start.
    await Promise.all([stack.trust.load(), stack.historyMarks.load()]).catch((error) => console.warn('local state load failed', error));
    await history.hydrateFromCache();
    await archives.load();
    ui.showApp();
    history.loadConversations();
    history.startPolling();
    realtime.connect();
    stack.prekeys.start();
  }

  function reset() {
    messages.revokeAllBlobUrls();
    store.resetSession();
    stack.historyMarks.reset();
    stack.trust.reset();
    stack.prekeys.stop();
    realtime.disconnect();
    history.stopPolling();
    store.notify('session-reset');
  }

  // Wipes the identity and every other trace of VEIL from this browser
  // (src/platform/wipe.js) without touching the UI.
  async function purgeLocalIdentity() {
    reset();
    sessionStore.forget();
    state.muted.clear();
    state.archives = [];
    await wipeEverything({
      closeDatabase: () => idb.close(),
      indexedDB,
      localStorage: webStorage('localStorage'),
      sessionStorage: webStorage('sessionStorage'),
      caches: globalThis.caches,
      onBlocked: () => ui.toast(t('storage.wipeBlocked'), 'error'),
    });
  }

  return {
    enterApp,
    reset,

    // A handle and keys, nothing else: no profile text goes to the server.
    async register(handle) {
      const keys = await generateIdentity(crypto.subtle, { nowMs: apiClient.serverNow() });
      const registered = await stack.api('/auth/register', {
        method: 'POST',
        body: {
          handle,
          deviceName: 'web-' + (navigator.platform || 'browser'),
          platform: 'android',
          // The Ed25519 identity key and its signed prekey bundle (contract
          // C1), which peers fetch from /v1/keys to start a session.
          ...(await publishedKeys(crypto.subtle, keys)),
        },
      });
      // Saved before the first login: if that fails the registered keys are
      // still here and the auth screen can retry.
      await sessionStore.save({
        handle: registered.handle,
        userId: registered.userId,
        deviceId: registered.deviceId,
        ...keys,
        accessToken: null,
        refreshToken: null,
      });
      await apiClient.login(await sessionStore.getDeviceCredentials());
    },

    // Re-authenticates the stored identity with a fresh device challenge.
    // Resolves to false when this browser holds no identity.
    async restore() {
      const stored = await sessionStore.load();
      if (!stored) return false;
      if (!stored.edPrivKey || !(stored.ik || stored.xPrivKey)) {
        throw new Error('이 브라우저의 세션은 새 암호화 형식과 호환되지 않아요. 다시 등록해주세요.');
      }
      await apiClient.login(await sessionStore.getDeviceCredentials());
      await enterApp();
      return true;
    },

    // First sign-in of an identity a completed transfer just stored here.
    login: async () => apiClient.login(await sessionStore.getDeviceCredentials()),

    async end({ rejected = false } = {}) {
      await sessionStore.clearTokens();
      reset();
      await ui.showAuth({ rejected });
    },

    // Only for an explicit, confirmed wipe or a completed transfer.
    async destroyIdentity() {
      try {
        await purgeLocalIdentity();
      } catch (error) {
        ui.toast('일부 데이터를 지우지 못했어요: ' + error.message, 'error');
      }
      await ui.showAuth();
    },

    // After a completed transfer has written its session record over the one
    // stored here: clears everything else the replaced identity left, in
    // memory, in other tabs and in storage. Unlike a wipe it keeps the
    // database, so it waits on no other tab and leaves the new record.
    async clearReplacedIdentity() {
      identityChannel?.postMessage({ kind: 'identity-replaced' });
      reset();
      state.muted.clear();
      state.archives = [];
      await wipeInPlace({
        clearDatabase: () => idb.clearAllExcept(['session']),
        localStorage: webStorage('localStorage'),
        sessionStorage: webStorage('sessionStorage'),
        caches: globalThis.caches,
      });
    },

    // Raw row check: a record that fails to load (or migrate) still holds
    // keys and must not be overwritten without asking.
    async hasStoredIdentity() {
      if (sessionStore.current()) return true;
      try {
        return (await idb.get('session', 'me')) !== null;
      } catch {
        return false;
      }
    },
  };
}
