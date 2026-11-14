// The auth screen: register a new handle, continue (or retry) the identity
// stored in this browser, or delete it.

import { t } from '../../../i18n/i18n.js';
import { isValidHandle, normalizeHandle } from '../../domain/composer-text.js';
import { isAuthRejection } from '../../platform/api-client.js';
import { $ } from '../dom.js';
import { toast } from '../toast.js';

// session: src/app/services/session.js; confirm: src/ui/confirm.js.
export function createAuthView({ stack, session, confirm }) {
  async function show({ rejected = false } = {}) {
    $('auth-screen').classList.remove('hidden');
    $('app').classList.add('hidden');
    let stored = stack.sessionStore.current();
    if (!stored) {
      try {
        stored = await stack.sessionStore.load();
      } catch (error) {
        toast('세션 불러오기 실패: ' + error.message, 'error');
      }
    }
    $('restore-row').classList.toggle('hidden', !stored);
    if (stored) $('restore-handle').textContent = '@' + stored.handle;
    $('restore-rejected').classList.toggle('hidden', !(stored && rejected));
    $('restore-btn').textContent = t(rejected ? 'auth.restore.retry' : 'auth.restore.continue');
    // The wipe button stays whatever happened: a corrupted or half-restored
    // session must be removable without first restoring it.
  }

  // Asks before destroying the identity stored here. Resolves to whether it
  // was destroyed.
  async function confirmAndDestroyIdentity() {
    const handle = stack.sessionStore.current()?.handle;
    const ok = await confirm({
      title: t('auth.restore.delete'),
      body: handle
        ? `@${handle} 의 키와 이 브라우저의 VEIL 데이터를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.`
        : '이 브라우저의 VEIL 키와 데이터를 전부 삭제합니다.',
      okLabel: '삭제',
      destructive: true,
    });
    if (!ok) return false;
    await session.destroyIdentity();
    toast('키를 삭제했습니다');
    return true;
  }

  async function restore(failurePrefix) {
    try {
      return await session.restore();
    } catch (error) {
      toast(failurePrefix + error.message, 'error');
      await show({ rejected: isAuthRejection(error) });
      return true;
    }
  }

  return {
    show,
    confirmAndDestroyIdentity,

    mount() {
      $('register-form').addEventListener('submit', async (event) => {
        event.preventDefault();
        const handle = normalizeHandle($('reg-handle').value);
        if (!handle) return toast('핸들을 입력하세요', 'error');
        if (!isValidHandle(handle)) return toast('소문자, 숫자, _ 만 사용 (최대 32자)', 'error');
        // A new handle replaces the identity stored here, which destroys it.
        if ((await session.hasStoredIdentity()) && !(await confirmAndDestroyIdentity())) return;
        $('reg-btn').disabled = true;
        try {
          await session.register(handle);
          await session.enterApp();
          toast('환영합니다 @' + handle, 'good');
        } catch (error) {
          toast(error.message, 'error');
          if (stack.sessionStore.current()) await show({ rejected: isAuthRejection(error) });
        } finally {
          $('reg-btn').disabled = false;
        }
      });

      $('restore-btn').addEventListener('click', async () => {
        $('restore-btn').disabled = true;
        try {
          await restore('복원 실패: ');
        } finally {
          $('restore-btn').disabled = false;
        }
      });

      for (const id of ['restore-delete-btn', 'wipe-btn', 'legacy-new-identity']) {
        $(id).addEventListener('click', confirmAndDestroyIdentity);
      }
    },

    // The stored identity signs in again on load; without one, the auth
    // screen shows.
    async boot() {
      if (!(await restore('세션 복원 실패: '))) await show();
    },
  };
}
