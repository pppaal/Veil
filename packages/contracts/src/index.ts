import type {
  AttachmentDownloadTicket,
  AttachmentUploadTicket,
  CryptoEnvelope,
  EncryptedAttachmentReference,
  PublicKeyBundle,
} from '@veil/shared';
import type {
  AttachmentUploadStatus,
  ConversationType,
  DevicePlatform,
  MessageType,
  UserStatus,
} from '@veil/shared';

export interface RegisterRequest {
  handle: string;
  displayName?: string;
  deviceName: string;
  platform: DevicePlatform;
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
  pushToken?: string;
}

export interface RegisterResponse {
  userId: string;
  deviceId: string;
  handle: string;
  status: UserStatus;
}

export interface AuthChallengeRequest {
  handle: string;
  deviceId: string;
}

export interface AuthChallengeResponse {
  challengeId: string;
  challenge: string;
  expiresAt: string;
}

export interface AuthVerifyRequest {
  challengeId: string;
  deviceId: string;
  signature: string;
}

export interface AuthVerifyResponse {
  accessToken: string;
  refreshToken: string;
  deviceId: string;
  userId: string;
  expiresAt: string;
  refreshExpiresAt: string;
}

export interface AuthRefreshRequest {
  refreshToken: string;
}

export interface AuthRefreshResponse {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
  refreshExpiresAt: string;
}

export interface AuthLogoutRequest {
  refreshToken?: string;
}

export interface UserProfileResponse {
  id: string;
  handle: string;
  displayName?: string | null;
  avatarPath?: string | null;
  status: UserStatus;
  activeDeviceId?: string | null;
}

export interface KeyBundleResponse {
  user: UserProfileResponse;
  bundle: PublicKeyBundle;
  deviceBundles: PublicKeyBundle[];
}

export interface ConversationMemberSummary {
  userId: string;
  handle: string;
  displayName?: string | null;
}

export interface ConversationSummary {
  id: string;
  type: ConversationType;
  createdAt: string;
  members: ConversationMemberSummary[];
  lastMessage?: ConversationMessageSummary | null;
  // Default TTL (seconds) applied to new messages in this conversation.
  // null means disappearing messages are disabled.
  disappearingTimerSeconds?: number | null;
}

export interface CreateDirectConversationRequest {
  peerHandle: string;
}

export interface CreateDirectConversationResponse {
  conversation: ConversationSummary;
}

export interface SetDisappearingTimerRequest {
  // Positive integer = TTL in seconds. null = disable.
  seconds: number | null;
}

export interface SetDisappearingTimerResponse {
  conversation: ConversationSummary;
}

export interface MessageReactionSummary {
  userId: string;
  emoji: string;
}

export interface ConversationMessageSummary {
  id: string;
  clientMessageId?: string | null;
  conversationId: string;
  senderDeviceId: string;
  conversationOrder: number;
  ciphertext: string;
  nonce: string;
  messageType: MessageType;
  attachment?: EncryptedAttachmentReference | null;
  expiresAt?: string | null;
  // True when the message is view-once: the server hard-deletes it as
  // soon as any non-sender member marks it read.
  viewOnce?: boolean;
  serverReceivedAt: string;
  deletedAt?: string | null;
  deliveredAt?: string | null;
  readAt?: string | null;
  reactions?: MessageReactionSummary[];
}

export interface ListMessagesResponse {
  items: ConversationMessageSummary[];
  nextCursor?: string | null;
}

export interface SendMessageRequest {
  conversationId: string;
  clientMessageId: string;
  envelope: CryptoEnvelope;
}

export interface SendMessageResponse {
  message: ConversationMessageSummary;
  idempotent: boolean;
}

export interface MarkMessageReadResponse {
  messageId: string;
  readAt: string;
}

export interface DeleteLocalMessageResponse {
  messageId: string;
  acknowledged: true;
}

export interface CreateUploadTicketRequest {
  contentType: string;
  sizeBytes: number;
  sha256: string;
}

export interface CreateUploadTicketResponse {
  attachmentId: string;
  upload: AttachmentUploadTicket;
  constraints: {
    maxSizeBytes: number;
    allowedMimeTypes: string[];
  };
}

export interface CompleteAttachmentUploadRequest {
  attachmentId: string;
  uploadStatus: AttachmentUploadStatus;
}

export interface CompleteAttachmentUploadResponse {
  attachmentId: string;
  uploadStatus: AttachmentUploadStatus;
}

export interface AttachmentDownloadTicketResponse {
  ticket: AttachmentDownloadTicket;
}

export interface DeviceTransferInitRequest {
  oldDeviceId: string;
}

export interface DeviceTransferInitResponse {
  sessionId: string;
  transferToken: string;
  expiresAt: string;
}

export interface DeviceTransferApproveRequest {
  sessionId: string;
  claimId: string;
}

export interface DeviceTransferApproveResponse {
  sessionId: string;
  claimId: string;
  approved: true;
}

export interface DeviceTransferClaimRequest {
  sessionId: string;
  transferToken: string;
  newDeviceName: string;
  platform: DevicePlatform;
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
  authProof: string;
}

export interface DeviceTransferClaimResponse {
  sessionId: string;
  claimId: string;
  claimantFingerprint: string;
  expiresAt: string;
}

export interface DeviceTransferCompleteRequest {
  sessionId: string;
  transferToken: string;
  claimId: string;
  authProof: string;
}

export interface DeviceTransferCompleteResponse {
  sessionId: string;
  claimId: string;
  newDeviceId: string;
  revokedDeviceId?: string | null;
  preferredDeviceId?: string | null;
  handle: string;
  displayName?: string | null;
  completedAt: string;
}

export type DeviceTrustState = 'current' | 'preferred' | 'trusted' | 'stale' | 'revoked';

export interface RevokeDeviceRequest {
  deviceId: string;
}

export interface DeviceSummary {
  id: string;
  deviceName: string;
  platform: DevicePlatform;
  isActive: boolean;
  trustState: DeviceTrustState;
  revokedAt?: string | null;
  trustedAt?: string | null;
  joinedFromDeviceId?: string | null;
  joinedFromDeviceName?: string | null;
  joinedFromPlatform?: DevicePlatform | null;
  createdAt: string;
  lastSeenAt: string;
  lastSyncAt?: string | null;
  lastTrustedActivityAt?: string | null;
}

export interface ListDevicesResponse {
  items: DeviceSummary[];
  activeDeviceId?: string | null;
}

export interface RevokeDeviceResponse {
  deviceId: string;
  revokedAt: string;
}

export interface BlockedUserSummary {
  userId: string;
  handle: string;
  displayName?: string | null;
  blockedAt: string;
}

export interface ListBlockedUsersResponse {
  items: BlockedUserSummary[];
}

export interface BlockUserRequest {
  userId: string;
}

export interface BlockUserResponse {
  blocked: BlockedUserSummary;
}

export interface UnblockUserResponse {
  userId: string;
  unblocked: true;
}

export interface ConversationMuteSummary {
  conversationId: string;
  // null = muted indefinitely. ISO string = auto-unmutes at that time.
  mutedUntil: string | null;
}

export interface SetConversationMuteRequest {
  // null = unmute. number = seconds from now until auto-unmute (use a huge value for "forever" or omit for indefinite).
  mutedForSeconds: number | null | undefined;
}

export interface SetConversationMuteResponse {
  mute: ConversationMuteSummary | null;
}

export type AbuseReportReason =
  | 'spam'
  | 'harassment'
  | 'impersonation'
  | 'csam'
  | 'violence'
  | 'scam'
  | 'other';

export interface FileAbuseReportRequest {
  reportedUserId: string;
  conversationId?: string | null;
  messageId?: string | null;
  reason: AbuseReportReason;
  note?: string | null;
}

export interface FileAbuseReportResponse {
  reportId: string;
  filedAt: string;
}

export interface RealtimeEventMap {
  'message.new': ConversationMessageSummary;
  'message.delivered': { messageId: string; userId: string; deliveredAt: string };
  'message.read': { messageId: string; userId: string; readAt: string };
  'message.reaction': { messageId: string; userId: string; emoji: string; action: 'add' | 'remove' };
  'presence.update': { userId: string; status: 'online' | 'offline'; updatedAt: string };
  'typing.start': { conversationId: string; userId: string; handle: string };
  'typing.stop': { conversationId: string; userId: string; handle: string };
  'conversation.sync': { conversationId: string; reason: 'message' | 'membership' | 'refresh' };
  'conversation.timer.changed': { conversationId: string; disappearingTimerSeconds: number | null };
  'message.consumed': { messageId: string; conversationId: string; consumedAt: string };
  'call.incoming': { callId: string; conversationId: string; callType: 'voice' | 'video'; initiatorHandle: string };
  'call.ended': { callId: string; conversationId: string; duration: number };
  'story.new': { storyId: string; userId: string; contentType: string };
}
