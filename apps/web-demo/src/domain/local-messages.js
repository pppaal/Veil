// Own messages that exist only on this device until the server names them:
// they carry a local id, which is never a server id, never cached and never
// the target of a reply, reaction or edit.

const PENDING_PREFIX = '__pending__';

export const pendingId = (clientMessageId) => PENDING_PREFIX + clientMessageId;
export const isPendingId = (id) => Boolean(id?.startsWith(PENDING_PREFIX));
