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

// X3DH one-time prekeys. The server stores only the public half; the private
// key never leaves the owning device.
export interface OneTimePrekeyUpload {
  keyId: number;
  publicKey: string;
}

export interface UploadOneTimePrekeysRequest {
  prekeys: OneTimePrekeyUpload[];
}

export interface UploadOneTimePrekeysResponse {
  // How many of the submitted prekeys were newly stored (duplicates by
  // (device, keyId) are skipped).
  uploaded: number;
  // Remaining unconsumed prekeys after the upload, so the client knows
  // whether it still needs to replenish.
  available: number;
}

export interface OneTimePrekeyCountResponse {
  available: number;
}

// A claimed single-use prekey for the target's active device. `prekey` is null
// when the pool is depleted — the initiator then falls back to signed-prekey-
// only X3DH.
export interface ClaimOneTimePrekeyResponse {
  deviceId: string;
  prekey: OneTimePrekeyUpload | null;
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
  // Set when the sender re-encrypted this message. The current ciphertext
  // is the latest revision; we keep no server-side history.
  editedAt?: string | null;
  editCount?: number;
  // FK to another message in the same conversation when this is a reply.
  // Null when the parent was deleted; the UI shows "원본 삭제됨".
  replyToMessageId?: string | null;
  deliveredAt?: string | null;
  readAt?: string | null;
  reactions?: MessageReactionSummary[];
}

export interface ListMessagesResponse {
  items: ConversationMessageSummary[];
  nextCursor?: string | null;
}

export interface ListConversationsResponse {
  items: ConversationSummary[];
  nextCursor?: string | null;
}

export interface SendMessageRequest {
  conversationId: string;
  clientMessageId: string;
  envelope: CryptoEnvelope;
  replyToMessageId?: string | null;
  // Group Sender Keys (phase AB.2): the membership generation the sender
  // encrypted under. Required and validated against the conversation's
  // current epoch only when the group has opted into Sender Keys
  // (group_epoch_required / group_epoch_stale); ignored otherwise, so legacy
  // clients and direct conversations are unaffected.
  groupEpoch?: number;
}

export interface SendMessageResponse {
  message: ConversationMessageSummary;
  idempotent: boolean;
}

export interface EditMessageRequest {
  ciphertext: string;
  nonce: string;
  version: string;
}

export interface EditMessageResponse {
  message: ConversationMessageSummary;
}

export interface DeleteMessageResponse {
  messageId: string;
  deletedAt: string;
}

export interface MarkMessageReadResponse {
  messageId: string;
  readAt: string;
}

export interface AddReactionRequest {
  emoji: string;
}

export interface AddReactionResponse {
  reactionId: string;
  messageId: string;
  emoji: string;
}

export interface RemoveReactionResponse {
  messageId: string;
  acknowledged: boolean;
}

export interface UpdatePushTokenRequest {
  pushToken: string;
}

export interface UpdatePushTokenResponse {
  deviceId: string;
  updatedAt: string;
}

export interface ClearPushTokenResponse {
  deviceId: string;
  clearedAt: string;
}

// Account-recovery backup. The ciphertext is the opaque passphrase-sealed
// client envelope — the server stores and returns it but can never decrypt it.
export interface UpsertRecoveryBackupRequest {
  ciphertext: string;
  // Envelope format marker, e.g. "veilbak:v1".
  format?: string;
}

export interface UpsertRecoveryBackupResponse {
  updatedAt: string;
}

export interface RecoveryBackupResponse {
  ciphertext: string;
  format: string;
  updatedAt: string;
}

export interface DeleteRecoveryBackupResponse {
  deleted: boolean;
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

export type DeviceTransferStatus = 'pending' | 'claimed' | 'approved' | 'completed' | 'expired';

export interface DeviceTransferSessionStatusResponse {
  sessionId: string;
  status: DeviceTransferStatus;
  expiresAt: string;
  completedAt?: string | null;
  pendingClaim?: {
    claimId: string;
    claimantFingerprint: string;
    newDeviceName: string;
    platform: DevicePlatform;
    approvedAt?: string | null;
  } | null;
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

// Group Sender Keys chain-key distribution. Each encryptedChainKey is an
// opaque ciphertext produced under the sender↔recipient 1:1 ratchet session;
// the server relays and briefly buffers it but can never read the chain key.
export interface GroupKeyDistributionUpload {
  recipientUserId: string;
  encryptedChainKey: string;
  nonce: string;
  version: string;
}

export interface GroupKeyDistributeRequest {
  // Must equal the conversation's current epoch — distributions for a stale
  // membership generation are rejected with group_epoch_stale.
  epoch: number;
  distributions: GroupKeyDistributionUpload[];
}

export interface GroupKeyDistributeResponse {
  conversationId: string;
  epoch: number;
  accepted: number;
  // How long the server buffers each blob for offline recipients.
  expiresInSeconds: number;
}

export interface GroupKeyDistributionItem {
  fromUserId: string;
  fromDeviceId: string;
  encryptedChainKey: string;
  nonce: string;
  version: string;
  createdAt: string;
}

export interface GroupKeyDistributionsResponse {
  conversationId: string;
  epoch: number;
  distributions: GroupKeyDistributionItem[];
}

export interface RealtimeEventMap {
  'message.new': ConversationMessageSummary;
  'message.delivered': { messageId: string; userId: string; deliveredAt: string };
  'message.read': { messageId: string; userId: string; readAt: string };
  'message.reaction': {
    messageId: string;
    userId: string;
    emoji: string;
    action: 'add' | 'remove';
  };
  'message.edited': ConversationMessageSummary;
  'message.deleted': { messageId: string; deletedAt: string };
  'presence.update': { userId: string; status: 'online' | 'offline'; updatedAt: string };
  'typing.start': { conversationId: string; userId: string; handle: string };
  'typing.stop': { conversationId: string; userId: string; handle: string };
  'conversation.sync': { conversationId: string; reason: 'message' | 'membership' | 'refresh' };
  'conversation.timer.changed': { conversationId: string; disappearingTimerSeconds: number | null };
  'message.consumed': { messageId: string; conversationId: string; consumedAt: string };
  'call.incoming': {
    callId: string;
    conversationId: string;
    callType: 'voice' | 'video';
    initiatorHandle: string;
  };
  'call.ended': { callId: string; conversationId: string; duration: number };
  'call.accepted': { callId: string; conversationId: string };
  'call.declined': { callId: string; conversationId: string };
  // WebRTC signaling relay. `data` is an opaque SDP offer/answer or ICE
  // candidate blob: the server never parses, inspects, or stores it. Media is
  // negotiated end-to-end (DTLS-SRTP), so this channel only shuttles setup
  // material between the two parties.
  'call.signal': {
    callId: string;
    kind: 'offer' | 'answer' | 'ice';
    data: string;
    fromUserId: string;
    fromDeviceId: string;
  };
  'story.new': {
    storyId: string;
    userId: string;
    handle: string;
    displayName: string | null;
    contentType: string;
    createdAt: string;
    expiresAt: string;
  };
  // Group Sender Keys (design-only): emitted to all current members when a
  // group's membership generation changes. `epoch` is the new
  // conversations.current_epoch; `userId` is the member who joined or left.
  // Clients that don't implement Sender Keys yet ignore this event.
  'group.epoch.bumped': {
    conversationId: string;
    epoch: number;
    reason: 'join' | 'leave';
    userId: string;
  };
  // A sender-key chain-key distribution addressed to this user. The
  // encryptedChainKey is opaque to the server (1:1 ratchet ciphertext).
  // Recipients that were offline recover the same payload via
  // GET /v1/conversations/group/:id/key-distributions within the buffer TTL.
  'group.key.distribution': {
    conversationId: string;
    epoch: number;
    fromUserId: string;
    fromDeviceId: string;
    encryptedChainKey: string;
    nonce: string;
    version: string;
  };
}
