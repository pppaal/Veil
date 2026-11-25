// Abuse reports (POST /v1/safety/reports, contracts FileAbuseReportRequest).
// A report names who and what, and why from a fixed list: the server keeps
// no free-text note, and the reported message's content never leaves this
// device, so nothing a user types is sent with it.

export const REPORT_REASONS = Object.freeze(['spam', 'harassment', 'impersonation', 'csam', 'violence', 'scam', 'other']);

// The request body: these four fields and nothing else.
export function abuseReport({ reportedUserId, conversationId, messageId, reason }) {
  if (!REPORT_REASONS.includes(reason)) throw new TypeError(`unknown report reason: ${reason}`);
  return { reportedUserId, conversationId, messageId, reason };
}

// The member who sent `message`, the one a report or a block about it
// names: the other member of a direct conversation, for a message this
// device did not send. Null when that cannot be told, as in a group, where
// this client cannot map a sender's device to a member; then neither is
// offered rather than naming someone else.
export function senderToReport(conversation, message, self) {
  if (!conversation || conversation.type !== 'direct' || !self?.userId) return null;
  if (!message?.senderDeviceId || message.senderDeviceId === self.deviceId) return null;
  return conversation.members?.find((member) => member.userId !== self.userId) ?? null;
}
