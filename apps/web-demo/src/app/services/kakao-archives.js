// Imported KakaoTalk exports, kept on this device as read-only archives
// (src/platform/persist.js kakaoArchiveMeta): the sidebar reads only their
// meta rows, held in the store; the messages are read when one is opened.
// Nothing of an archive ever leaves the browser.

import { kakaoArchiveMeta } from '../../platform/persist.js';

export function createKakaoArchives({ store, stack }) {
  const { state } = store;

  async function load() {
    try {
      state.archives = await stack.idb.all('kakao-archive-meta');
    } catch {
      state.archives = [];
    }
  }

  return {
    load,

    // parsed: lib/kakao-import.js parseKakaoExport output.
    async save(title, parsed) {
      const archive = {
        id: 'kakao-' + Date.now().toString(36),
        title,
        importedAt: new Date().toISOString(),
        participants: parsed.participants,
        messageCount: parsed.messages.filter((message) => message.kind === 'msg').length,
        messages: parsed.messages,
      };
      await stack.idb.put('kakao-archives', archive);
      await stack.idb.put('kakao-archive-meta', kakaoArchiveMeta(archive));
    },

    open: (id) => stack.idb.get('kakao-archives', id).catch(() => null),
  };
}
