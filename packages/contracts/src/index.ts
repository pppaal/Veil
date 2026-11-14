import type {
  AttachmentDownloadTicket,
  AttachmentUploadTicket,
  CryptoEnvelope,
  EncryptedAttachmentReference as SharedEncryptedAttachmentReference,
} from '@veil/shared';
import type {
  AttachmentUploadStatus,
  ConversationType,
  DevicePlatform,
  MemberRole,
  MessageType,
  UserStatus,
} from '@veil/shared';

export type VeilErrorCode =
  | 'unauthorized'
  | 'validation_failed'
  | 'handle_taken'
  | 'handle_not_found'
  | 'active_device_not_found'
  | 'device_not_found'
  | 'challenge_invalid'
  | 'device_not_active'
  | 'invalid_device_signature'
  | 'signed_prekey_timestamp_out_of_window'
  | 'device_forbidden'
  | 'conversation_membership_required'
  | 'conversation_role_required'
  | 'envelope_context_mismatch'
  | 'envelope_version_mismatch'
  | 'envelope_version_forbidden'
  | 'direct_peer_mismatch'
  | 'message_not_found'
  | 'attachment_not_found'
  | 'attachment_forbidden'
  | 'attachment_upload_invalid'
  | 'attachment_id_conflict'
  | 'transfer_session_not_found'
  | 'transfer_session_inactive'
  | 'transfer_token_invalid'
  | 'transfer_claim_required'
  | 'transfer_claim_invalid'
  | 'transfer_approval_required'
  | 'transfer_completion_invalid'
  | 'internal_error'
  | 'profile_not_found'
  | 'cannot_add_self'
  | 'contact_already_exists'
  | 'contact_not_found'
  | 'story_not_found'
  | 'story_forbidden'
  | 'story_already_viewed'
  | 'refresh_token_invalid'
  | 'token_revoked'
  | 'peer_unreachable'
  | 'call_not_found'
  | 'call_invalid_state'
  | 'call_initiator_forbidden'
  | 'call_not_allowed'
  | 'message_not_owned'
  | 'message_deleted'
  | 'view_once_immutable'
  | 'edit_window_expired'
  | 'reply_target_invalid'
  | 'owner_immutable'
  | 'group_not_found'
  | 'group_member_limit'
  | 'group_epoch_required'
  | 'group_epoch_stale'
  | 'group_sender_keys_disabled'
  | 'sender_keys_irreversible'
  | 'key_distribution_invalid'
  | 'channel_not_found'
  | 'resource_conflict'
  | 'resource_not_found'
  | 'reactions_e2e_only'
  | 'profile_e2e_pending'
  | 'story_audience_invalid'
  | 'origin_not_allowed'
  | 'secret_storage_full'
  | 'secret_quota_exceeded';

// The single HTTP status of every error code. Clients branch on `code`; the
// status is derived from this table so one code can never surface with two
// different statuses depending on which endpoint raised it.
export const ERROR_CATALOG: Readonly<Record<VeilErrorCode, number>> = Object.freeze({
  unauthorized: 401,
  validation_failed: 400,
  handle_taken: 409,
  handle_not_found: 404,
  active_device_not_found: 404,
  device_not_found: 404,
  challenge_invalid: 401,
  device_not_active: 401,
  invalid_device_signature: 401,
  // PUT /keys/signed-prekey: spkTs must lie in [server now - 1 h, server now
  // + 10 min]. Clients stamp it from a clock corrected by the HTTP Date
  // header, so on this code they refresh that offset and draw a successor.
  signed_prekey_timestamp_out_of_window: 400,
  device_forbidden: 403,
  conversation_membership_required: 403,
  conversation_role_required: 403,
  envelope_context_mismatch: 403,
  envelope_version_mismatch: 400,
  envelope_version_forbidden: 400,
  direct_peer_mismatch: 403,
  message_not_found: 404,
  attachment_not_found: 404,
  attachment_forbidden: 403,
  attachment_upload_invalid: 400,
  attachment_id_conflict: 409,
  transfer_session_not_found: 404,
  transfer_session_inactive: 403,
  transfer_token_invalid: 401,
  transfer_claim_required: 403,
  transfer_claim_invalid: 401,
  transfer_approval_required: 403,
  transfer_completion_invalid: 401,
  internal_error: 500,
  profile_not_found: 404,
  cannot_add_self: 400,
  contact_already_exists: 409,
  contact_not_found: 404,
  story_not_found: 404,
  story_forbidden: 403,
  story_already_viewed: 409,
  refresh_token_invalid: 401,
  token_revoked: 401,
  peer_unreachable: 403,
  call_not_found: 404,
  call_invalid_state: 409,
  call_initiator_forbidden: 403,
  call_not_allowed: 403,
  message_not_owned: 403,
  message_deleted: 403,
  view_once_immutable: 403,
  edit_window_expired: 403,
  reply_target_invalid: 400,
  owner_immutable: 409,
  group_not_found: 404,
  group_member_limit: 409,
  group_epoch_required: 400,
  group_epoch_stale: 409,
  group_sender_keys_disabled: 400,
  sender_keys_irreversible: 400,
  key_distribution_invalid: 400,
  channel_not_found: 404,
  resource_conflict: 409,
  resource_not_found: 404,
  // Reactions are end-to-end encrypted messages now (messageType 'reaction').
  reactions_e2e_only: 410,
  // Profile text returns once it can be stored end-to-end encrypted.
  profile_e2e_pending: 410,
  story_audience_invalid: 400,
  // A browser request from an origin the relay does not serve. Refused before
  // any handler runs.
  origin_not_allowed: 403,
  // POST /s: one-time links already hold the relay's whole budget for them;
  // a new one fits once others are opened or expire.
  secret_storage_full: 503,
  // POST /s: the caller's network (an IPv4 address or an IPv6 /64) has used
  // its one-time-link quota for the UTC day; it renews at 00:00 UTC.
  secret_quota_exceeded: 429,
});

export interface RegisterRequest {
  handle: string;
  /** @deprecated Accepted for older clients and ignored; the server stores no display names. */
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
  status: UserStatus;
}

// GET /profile. Profile text (display name, bio, status, avatar) is not
// stored until it can be stored end-to-end encrypted.
export interface ProfileResponse {
  userId: string;
  handle: string;
}

/**
 * Which devices of the target get a one-time prekey claimed by
 * GET /keys/:handle:
 * - active: only the user's active device (the default);
 * - all: every trusted device, for per-device sessions;
 * - none: identity and signed prekeys only, nothing consumed.
 */
export const KEY_CLAIM_MODES = ['active', 'all', 'none'] as const;
export type KeyClaimMode = (typeof KEY_CLAIM_MODES)[number];

export interface KeysDevice {
  deviceId: string;
  identityPublicKey: string;
  signedPrekeyBundle: string;
  /** True for the device that represents the user right now (user.activeDeviceId). */
  isActive: boolean;
  /**
   * Null when the mode did not select this device, the pool is empty, or a
   * claim budget is spent; the initiator then runs signed-prekey-only X3DH.
   */
  oneTimePrekey: OneTimePrekeyUpload | null;
}

// GET /keys/:handle, the authenticated key directory.
export interface KeysResponse {
  user: {
    id: string;
    handle: string;
    activeDeviceId: string;
  };
  /** Trusted, non-revoked devices, most recently trusted first. */
  devices: KeysDevice[];
}

// GET /keys/group/:conversationId: the key directory of a group, for one
// Sender Keys distribution round. Only a current member of a group may read
// it; anyone else gets group_not_found (404), whether or not the id exists.
export interface GroupMemberKeysResponse {
  conversationId: string;
  /** The group's currentEpoch, read in the same snapshot as the members. */
  epoch: number;
  /**
   * One entry per current member except the caller, devices chosen as in
   * GET /keys/:handle. Nothing is claimed: every oneTimePrekey is null and no
   * directory budget is spent. A member with no trusted device is left out.
   */
  members: KeysResponse[];
}

export interface RotateSignedPrekeyRequest {
  signedPrekeyBundle: string;
}

export interface RotateSignedPrekeyResponse {
  deviceId: string;
  spkId: number;
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
  // Group Sender Keys (phase AB.3). Present only for `type === 'group'`.
  // `useSenderKeys` tells clients whether sends must carry `groupEpoch` and
  // use the `veil-group-v1` envelope; `currentEpoch` is the membership
  // generation the server will accept for the next send.
  useSenderKeys?: boolean;
  currentEpoch?: number;
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

// The only attachment reference the relay stores or returns. Content type,
// size, digest and the wrapped content key travel inside the authenticated
// E2E payload; clients must take attachment metadata from there.
export interface OuterAttachmentPointer {
  attachmentId: string;
}

/**
 * @deprecated Pre-W1 outer attachment metadata. The relay now accepts these
 * fields only for compatibility and discards everything except
 * `attachmentId`; use {@link OuterAttachmentPointer}.
 */
export type EncryptedAttachmentReference = SharedEncryptedAttachmentReference;

export interface ConversationMessageSummary {
  id: string;
  clientMessageId?: string | null;
  conversationId: string;
  senderDeviceId: string;
  conversationOrder: number;
  // Envelope format the sender used (e.g. 'veil-group-v1'); receivers pick
  // their decryptor from it.
  version: string;
  ciphertext: string;
  nonce: string;
  messageType: MessageType;
  attachment?: OuterAttachmentPointer | null;
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
  // The requesting viewer's own receipt only; never another member's.
  // Always null in realtime broadcasts.
  deliveredAt?: string | null;
  readAt?: string | null;
}

export interface ListMessagesResponse {
  items: ConversationMessageSummary[];
  nextCursor?: string | null;
}

export interface ListConversationsResponse {
  items: ConversationSummary[];
  nextCursor?: string | null;
}

export interface ChannelAdminSummary {
  userId: string;
  handle: string;
}

export interface ChannelMemberSummary extends ConversationMemberSummary {
  role: MemberRole;
}

// GET /conversations/channel/:id. Subscribers never see each other: the full
// member list is returned only to the owner and admins, and the latest post
// only to members.
export interface ChannelSummaryResponse {
  id: string;
  name: string;
  description: string | null;
  isPublic: boolean;
  /** Every member of the channel, the owner and admins included. */
  subscriberCount: number;
  admins: ChannelAdminSummary[];
  viewerRole: MemberRole | null;
  members?: ChannelMemberSummary[];
  lastMessage?: ConversationMessageSummary | null;
}

export interface TransferGroupOwnershipRequest {
  userId: string;
}

export interface TransferGroupOwnershipResponse {
  conversationId: string;
  ownerUserId: string;
  previousOwnerUserId: string;
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

// A reaction is an ordinary end-to-end encrypted message with messageType
// 'reaction'. Its inner payload (kind 'reaction') carries this body; the
// relay never parses it, and POST/DELETE /messages/:id/reactions answer 410
// reactions_e2e_only.
export interface ReactionPayload {
  v: 1;
  /** Id of the message the reaction applies to, in the same conversation. */
  target: string;
  emoji: string;
  op: 'add' | 'remove';
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

export interface DeleteLocalMessageResponse {
  messageId: string;
  acknowledged: true;
}

export interface CreateUploadTicketRequest {
  // Client-proposed UUID v4. Protocol v2 binds the attachment id into the
  // blob's AAD, so the client must know it before sealing. Omitted, the
  // relay assigns one.
  attachmentId?: string;
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
  /**
   * The old device's Ed25519 signature, with the auth key it logs in with,
   * over `transfer-approve:<sessionId>:<claimId>:<claimantFingerprint>`
   * (the fingerprint exactly as the claim and status responses give it). A
   * stolen bearer token alone cannot approve a transfer. Required by every
   * relay: without it the approval is refused with 401
   * `invalid_device_signature`.
   */
  approvalProof?: string;
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

/**
 * Proof that a request comes from the device itself, not only from someone
 * holding its bearer token: a challenge from POST /auth/challenge for the
 * calling device, signed with its auth key over `<purpose>:<challengeId>:<challenge>`.
 * The challenge is single-use and consumed whether or not the signature
 * holds. Required by every relay for the irreversible requests that name it:
 * without it they are refused with 401 `challenge_invalid`.
 */
export interface DeviceStepUpProof {
  challengeId?: string;
  signature?: string;
}

/**
 * Revoking the calling device, or the account's last active device, needs a
 * step-up proof with purpose `device-revoke:<deviceId>`.
 */
export interface RevokeDeviceRequest extends DeviceStepUpProof {
  deviceId: string;
}

/** DELETE /account body: a step-up proof with purpose `account-delete`. */
export type DeleteAccountRequest = DeviceStepUpProof;

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
  /** @deprecated Accepted for older clients and never stored: no one would read it. */
  note?: string | null;
}

export interface FileAbuseReportResponse {
  reportId: string;
  filedAt: string;
}

export interface AddContactRequest {
  handle: string;
  /** @deprecated Accepted for older clients and ignored: names for contacts stay on the device. */
  nickname?: string;
}

export interface ContactSummary {
  handle: string;
  addedAt: string;
}

// Upper bounds of a story: the ciphertext of one sealed envelope, and the
// number of contacts it can be addressed to.
export const STORY_MAX_CIPHERTEXT_LENGTH = 65536;
export const STORY_MAX_AUDIENCE = 500;

// POST /stories. The story is end-to-end encrypted by the client; the server
// stores the ciphertext for the listed audience only. Every audience member
// must be a mutual contact that neither side has blocked, otherwise
// 400 story_audience_invalid.
export interface CreateStoryRequest {
  ciphertext: string;
  envelopeVersion: string;
  audienceUserIds: string[];
}

export interface StorySummary {
  id: string;
  userId: string;
  handle: string;
  ciphertext: string;
  envelopeVersion: string;
  viewedByMe: boolean;
  /** How many audience members viewed it; only the author is told. */
  viewCount: number | null;
  createdAt: string;
  expiresAt: string;
}

export interface CreateStoryResponse {
  id: string;
  envelopeVersion: string;
  audienceSize: number;
  createdAt: string;
  expiresAt: string;
}

// Group Sender Keys chain-key distribution. Each encryptedChainKey is an
// opaque ciphertext produced under the sender↔recipient 1:1 ratchet session;
// the server relays and briefly buffers it but can never read the chain key.
export interface GroupKeyDistributionUpload {
  recipientUserId: string;
  // Addresses the blob to one of the recipient's devices. Omitted for the
  // legacy user-scoped path, where any of the recipient's devices may pick
  // it up.
  recipientDeviceId?: string | null;
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
  recipientDeviceId: string | null;
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
  /**
   * @deprecated Never emitted. Reactions arrive as 'message.new' with
   * messageType 'reaction'; the key stays so older clients' event lists
   * remain aligned with the contract.
   */
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
  // Sent only to the story's audience; the story itself is fetched (as
  // ciphertext) through GET /stories.
  'story.new': {
    storyId: string;
    userId: string;
    handle: string;
    envelopeVersion: string;
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
