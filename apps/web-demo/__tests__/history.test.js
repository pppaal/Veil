// History is fetched a page at a time, newest first, back to what the device
// already has, and merged into what it holds rather than replacing it.

import { describe, expect, it } from 'vitest';

import { fetchHistory, HISTORY_MAX_PAGES, HISTORY_PAGE_SIZE, mergeHistory } from '../src/domain/history.js';

const message = (order, extra = {}) => ({ id: `m-${order}`, clientMessageId: `c-${order}`, conversationOrder: order, ...extra });

// GET /conversations/:id/messages over orders 1..count, as the API pages.
function relay(count) {
  const all = Array.from({ length: count }, (_, i) => message(i + 1));
  const queries = [];
  const fetchPage = async (query) => {
    queries.push(query);
    const params = new URLSearchParams(query);
    const limit = Number(params.get('limit'));
    const before = params.get('cursor') ? all.find((m) => m.id === params.get('cursor')).conversationOrder : Infinity;
    const page = all.filter((m) => m.conversationOrder < before).slice(-limit);
    return { items: page, nextCursor: page.length === limit ? page[0].id : null };
  };
  return { fetchPage, queries };
}

const orders = (list) => list.map((m) => m.conversationOrder);
const range = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

describe('fetchHistory', () => {
  it('pages back through a backlog to what the device has, oldest first', async () => {
    const { fetchPage, queries } = relay(263);
    expect(orders(await fetchHistory(fetchPage, { through: 1 }))).toEqual(range(1, 263));
    expect(queries).toHaveLength(Math.ceil(263 / HISTORY_PAGE_SIZE));
    expect(queries[0]).toBe(`limit=${HISTORY_PAGE_SIZE}`);
    expect(queries[1]).toBe(`limit=${HISTORY_PAGE_SIZE}&cursor=m-214`);
  });

  it('stops at the first page that reaches what the device has', async () => {
    const { fetchPage, queries } = relay(263);
    expect(orders(await fetchHistory(fetchPage, { through: 200 }))).toEqual(range(164, 263));
    expect(queries).toHaveLength(2);
    expect(orders(await fetchHistory(fetchPage, { through: 263 }))).toEqual(range(214, 263));
  });

  it('fetches from the start of a conversation it has nothing of', async () => {
    const { fetchPage } = relay(120);
    expect(orders(await fetchHistory(fetchPage))).toEqual(range(1, 120));
  });

  it('pages back a bounded number of times', async () => {
    const { fetchPage, queries } = relay(HISTORY_PAGE_SIZE * (HISTORY_MAX_PAGES + 5));
    const items = await fetchHistory(fetchPage, { through: 1 });
    expect(queries).toHaveLength(HISTORY_MAX_PAGES);
    expect(items).toHaveLength(HISTORY_PAGE_SIZE * HISTORY_MAX_PAGES);
  });
});

describe('mergeHistory', () => {
  const view = (raw) => ({ ...raw, kind: 'text' });

  it('keeps what lies outside the fetched range, in conversation order', () => {
    const held = [message(1), message(2), message(90), message(140)];
    const items = [message(100), message(101), message(102)];
    expect(orders(mergeHistory(held, items, items.map(view)))).toEqual([1, 2, 90, 100, 101, 102, 140]);
  });

  it('lets the fetched range replace what was held for it', () => {
    const held = [message(1), message(100, { kind: 'locked' }), message(101), message(102)];
    const items = [message(100), message(102)];
    const merged = mergeHistory(held, items, items.map(view));
    expect(orders(merged)).toEqual([1, 100, 102]);
    expect(merged[1].kind).toBe('text');
    // An id the relay now files under another order is not shown twice.
    expect(orders(mergeHistory([message(5)], [{ ...message(5), conversationOrder: 100 }], [view({ ...message(5), conversationOrder: 100 })])))
      .toEqual([100]);
  });

  it('keeps sends the server has not acknowledged, after the history', () => {
    const pending = { id: '__pending__c-x', clientMessageId: 'c-x', _status: 'pending' };
    const failed = { id: '__pending__c-y', clientMessageId: 'c-y', _status: 'failed' };
    const acknowledged = { id: '__pending__c-101', clientMessageId: 'c-101', _status: 'pending' };
    const items = [message(100), message(101)];
    expect(mergeHistory([message(1), pending, failed, acknowledged], items, items.map(view)).map((m) => m.id))
      .toEqual(['m-1', 'm-100', 'm-101', '__pending__c-x', '__pending__c-y']);
  });

  it('keeps everything held when the relay serves nothing', () => {
    const held = [message(1), message(2)];
    expect(mergeHistory(held, [], [])).toEqual(held);
  });
});
