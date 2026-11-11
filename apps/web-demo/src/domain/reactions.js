// Reactions are end-to-end encrypted control messages: messageType
// 'reaction', inner kind 'reaction', body the compact JSON
//   {"v":1,"target":<messageId>,"emoji":<at most 8 code points>,"op":"add"|"remove"}
// The server relays them as ciphertext like any message, so it never learns
// who reacted to what, and no REST reaction endpoint is ever called. A
// reaction never renders as a bubble: it changes the reactions its target
// shows, the last one from each sender winning.

const REACTION_VERSION = 1;
// Counted in code points, as mobile counts runes: a ZWJ sequence such as a
// family emoji is 7 code points but 11 UTF-16 units.
const MAX_EMOJI_CODE_POINTS = 8;
const OPS = new Set(['add', 'remove']);
const MESSAGE_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

export function encodeReaction({ target, emoji, op }) {
  return JSON.stringify({ v: REACTION_VERSION, target, emoji, op });
}

// The reaction a peer sent, or null when the body is not one.
export function decodeReaction(body) {
  let value;
  try {
    value = JSON.parse(body);
  } catch {
    return null;
  }
  if (value === null || typeof value !== 'object' || value.v !== REACTION_VERSION) return null;
  const { target, emoji, op } = value;
  if (typeof target !== 'string' || !MESSAGE_ID_RE.test(target) || !OPS.has(op)) return null;
  if (typeof emoji !== 'string' || emoji.length === 0 || [...emoji].length > MAX_EMOJI_CODE_POINTS) return null;
  return { target, emoji, op };
}

// What tapping `emoji` on `target` sends, given the user's current reaction
// there: the same emoji again takes it back.
export function toggledReaction({ target, emoji, current }) {
  return { target, emoji, op: current === emoji ? 'remove' : 'add' };
}

// Folds one conversation's messages, in order, into the reactions each
// target shows: Map<targetId, [{ senderDeviceId, emoji }]>. Reactions name
// targets by id, so only targets in this same conversation are affected.
export function reactionsByTarget(messages) {
  const latest = new Map(); // targetId -> Map<senderDeviceId, emoji>
  for (const message of messages) {
    const reaction = message.kind === 'reaction' ? message.reaction : null;
    if (!reaction) continue;
    const bySender = latest.get(reaction.target) ?? new Map();
    if (reaction.op === 'add') bySender.set(message.senderDeviceId, reaction.emoji);
    else bySender.delete(message.senderDeviceId);
    latest.set(reaction.target, bySender);
  }
  const shown = new Map();
  for (const [target, bySender] of latest) {
    if (bySender.size > 0) shown.set(target, [...bySender].map(([senderDeviceId, emoji]) => ({ senderDeviceId, emoji })));
  }
  return shown;
}
