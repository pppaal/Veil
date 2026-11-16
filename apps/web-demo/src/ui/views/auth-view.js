// The auth screen: register a new handle, continue (or retry) the account
// stored in this browser, or remove it. Also the two confirmations that
// destroy that account: Remove (from the auth screen) and Sign out (from
// the menu, with moving it elsewhere as the safe alternative).

import { t } from '../../../i18n/i18n.js';
import { isValidHandle, normalizeHandle } from '../../domain/composer-text.js';
import { isAuthRejection } from '../../platform/api-client.js';
import { $, avatarFor } from '../dom.js';
import { toast } from '../toast.js';

// What a failed registration says: a taken handle, or that it did not work.
// The server's own wording never reaches the screen.
const registrationError = (error) => t(error?.code === 'handle_taken' ? 'auth.form.handle.taken' : 'auth.form.failed');

// session: src/app/services/session.js; confirm: src/ui/confirm.js.
export function createAuthView({ stack, session, confirm }) {
  async function show({ rejected = false } = {}) {
    $('auth-screen').classList.remove('hidden');
    $('app').classList.add('hidden');
    let stored = stack.sessionStore.current();
    if (!stored) {
      try {
        stored = await stack.sessionStore.load();
      } catch {
        toast(t('auth.restore.loadFailed'), 'error');
      }
    }
    const handle = stored?.handle;
    $('restore-row').classList.toggle('hidden', !handle);
    if (handle) {
      $('restore-handle').textContent = '@' + handle;
      $('restore-avatar').replaceChildren(avatarFor(handle, 'md'));
      $('restore-rejected-text').textContent = t('auth.restore.rejected', { handle });
    }
    // A rejected account offers Try again and Remove in its notice, instead
    // of Continue and the line under the row.
    const refused = Boolean(handle && rejected);
    $('restore-rejected').classList.toggle('hidden', !refused);
    $('restore-btn').classList.toggle('hidden', refused);
    // The remove action shows whenever something is stored, so a corrupted
    // or half-restored account can go without first signing in to it.
    const anythingStored = Boolean(stored) || (await session.hasStoredIdentity());
    const wipe = $('wipe-btn');
    wipe.classList.toggle('hidden', !anythingStored || refused);
    wipe.textContent = handle ? t('auth.wipe', { handle }) : t('auth.wipe.noHandle');
  }

  // Asks before removing the account stored here. Resolves to whether it
  // was removed.
  async function confirmAndRemove() {
    const handle = stack.sessionStore.current()?.handle;
    const ok = await confirm({
      title: handle ? t('auth.wipe.title', { handle }) : t('auth.wipe.titleNoHandle'),
      body: handle ? t('auth.wipe.bodyHandle', { handle }) : t('auth.wipe.body'),
      okLabel: t('auth.wipe.ok'),
      destructive: true,
    });
    if (!ok) return false;
    await session.destroyIdentity();
    toast(t('auth.wipe.done'));
    return true;
  }

  // Signing out deletes the only copy of the account, so the dialog offers
  // to move it to another device instead (onMove).
  async function confirmAndSignOut(onMove) {
    const handle = stack.sessionStore.current()?.handle;
    if (!handle) return confirmAndRemove();
    const ok = await confirm({
      title: t('signOut.title', { handle }),
      body: t('signOut.body', { handle }),
      okLabel: t('signOut.confirm'),
      destructive: true,
      alternative: { label: t('signOut.move'), onChoose: onMove },
    });
    if (!ok) return false;
    await session.destroyIdentity();
    toast(t('signOut.done'));
    return true;
  }

  // failureKey: the message of a sign-in that failed.
  async function restore(failureKey) {
    try {
      return await session.restore();
    } catch (error) {
      toast(t(failureKey), 'error');
      await show({ rejected: isAuthRejection(error) });
      return true;
    }
  }

  async function retry(button) {
    button.disabled = true;
    try {
      await restore('auth.restore.failed');
    } finally {
      button.disabled = false;
    }
  }

  return {
    show,
    confirmAndRemove,
    confirmAndSignOut,

    mount() {
      $('register-form').addEventListener('submit', async (event) => {
        event.preventDefault();
        const handle = normalizeHandle($('reg-handle').value);
        if (!handle) return toast(t('auth.form.handle.missing'), 'error');
        if (!isValidHandle(handle)) return toast(t('auth.form.handle.invalid'), 'error');
        // A new handle replaces the account stored here, which destroys it.
        if ((await session.hasStoredIdentity()) && !(await confirmAndRemove())) return;
        $('reg-btn').disabled = true;
        try {
          await session.register(handle);
          $('reg-handle').value = '';
          await session.enterApp();
        } catch (error) {
          // Registered but not signed in: the account is stored, and the
          // auth screen offers to try again.
          const registered = Boolean(stack.sessionStore.current());
          toast(registered ? t('auth.restore.failed') : registrationError(error), 'error');
          if (registered) await show({ rejected: isAuthRejection(error) });
        } finally {
          $('reg-btn').disabled = false;
        }
      });

      $('restore-btn').addEventListener('click', (event) => retry(event.currentTarget));
      $('restore-retry').addEventListener('click', (event) => retry(event.currentTarget));
      for (const id of ['restore-remove', 'wipe-btn', 'legacy-new-identity']) {
        $(id).addEventListener('click', confirmAndRemove);
      }
    },

    // The stored account signs in again on load; without one, the auth
    // screen shows.
    async boot() {
      if (!(await restore('auth.restore.bootFailed'))) await show();
    },
  };
}
