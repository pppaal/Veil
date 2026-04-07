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
  deviceId: string;
  userId: string;
  expiresAt: string;
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
}

export interface CreateDirectConversationRequest {
  peerHandle: string;
}

export interface CreateDirectConversationResponse {
  conversation: ConversationSummary;
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
  serverReceivedAt: string;
  deletedAt?: string | null;
  deliveredAt?: string | null;
  readAt?: string | null;
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

export interface RealtimeEventMap {
  'message.new': ConversationMessageSummary;
  'message.delivered': { messageId: string; userId: string; deliveredAt: string };
  'message.read': { messageId: string; userId: string; readAt: string };
  'presence.update': { userId: string; status: 'online' | 'offline'; updatedAt: string };
  'conversation.sync': { conversationId: string; reason: 'message' | 'membership' | 'refresh' };
}
