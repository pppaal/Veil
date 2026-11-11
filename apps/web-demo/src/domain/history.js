// A conversation's history from the relay: GET /conversations/:id/messages
// answers with the newest page, in conversation order, and while the page is
// full a cursor to the page before it.
//
// A refresh pages back until it reaches the history this device already has,
// so a backlog longer than a page is fetched whole. That is what lets it be
// opened at all: one frame may stash at most 200 skipped keys
// (src/crypto/ratchet.js), so a chain must be opened in order, from the
// oldest frame up, never from the top of a long backlog down.

export const HISTORY_PAGE_SIZE = 50;
// How far back one refresh pages at most (2000 messages): a bound on a relay
// that keeps handing out cursors.
export const HISTORY_MAX_PAGES = 40;

// fetchPage(query) -> { items, nextCursor } for the query string of one page.
// `through` is the conversationOrder up to which this device already has the
// history. Resolves to the raw items, oldest first.
export async function fetchHistory(fetchPage, { through = 0 } = {}) {
  const pages = [];
  let cursor = null;
  for (let page = 0; page < HISTORY_MAX_PAGES; page += 1) {
    const query = new URLSearchParams({ limit: String(HISTORY_PAGE_SIZE), ...(cursor ? { cursor } : {}) });
    const { items = [], nextCursor = null } = await fetchPage(query.toString());
    pages.unshift(items);
    if (!nextCursor || items.length === 0 || items[0].conversationOrder <= through) break;
    cursor = nextCursor;
  }
  return pages.flat();
}

// The list a conversation shows after a refresh: `views` (those of the
// fetched `items`) replace what was held for the range they cover; held
// messages before or after it stay (history the relay no longer serves lives
// on here, and a live message may have arrived meanwhile), in conversation
// order, followed by our sends the server has not acknowledged yet.
export function mergeHistory(held, items, views) {
  const oldest = items[0]?.conversationOrder ?? Infinity;
  const newest = items.at(-1)?.conversationOrder ?? -Infinity;
  const fetched = new Set(items.map((m) => m.id));
  const seenClientIds = new Set(items.map((m) => m.clientMessageId));
  const kept = held.filter((m) => !fetched.has(m.id) && (m.conversationOrder < oldest || m.conversationOrder > newest));
  const pendings = held.filter(
    (m) => (m._status === 'pending' || m._status === 'failed') && !seenClientIds.has(m.clientMessageId),
  );
  return [...[...kept, ...views].sort((a, b) => a.conversationOrder - b.conversationOrder), ...pendings];
}
