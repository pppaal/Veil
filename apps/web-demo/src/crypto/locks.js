// Serializes crypto operations by name. Every tab of this origin shares the
// session store, so a ratchet step must hold the conversation's lock across
// read, step and write: navigator.locks makes that hold across tabs. Where
// the Web Locks API is missing, a keyed in-tab mutex still serializes this
// tab's own work.

export const conversationLockName = (conversationId) => `veil-crypto:${conversationId}`;

export function createLocks(nativeLocks) {
  const tails = new Map();

  function runInTab(name, task) {
    const previous = tails.get(name) ?? Promise.resolve();
    const run = previous.then(() => task());
    const tail = run.catch(() => {});
    tails.set(name, tail);
    tail.then(() => {
      if (tails.get(name) === tail) tails.delete(name);
    });
    return run;
  }

  return {
    run(name, task) {
      return typeof nativeLocks?.request === 'function'
        ? nativeLocks.request(name, () => task())
        : runInTab(name, task);
    },
  };
}
