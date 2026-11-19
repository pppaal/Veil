import type { MessageType } from '@veil/shared';

// Message types that never wake a device. A reaction is not worth waking a
// phone for, and a wake per reaction would show the push provider each moment
// someone reacted, on top of every real message.
const SILENT_MESSAGE_TYPES: ReadonlySet<MessageType> = new Set<MessageType>(['reaction']);

/** Whether a newly relayed message of this type may wake offline recipients. */
export const wakesRecipient = (messageType: MessageType): boolean =>
  !SILENT_MESSAGE_TYPES.has(messageType);
