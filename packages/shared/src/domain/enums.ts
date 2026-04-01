export const userStatuses = ['active', 'locked', 'revoked'] as const;
export type UserStatus = (typeof userStatuses)[number];

export const devicePlatforms = ['ios', 'android', 'windows', 'macos', 'linux'] as const;
export type DevicePlatform = (typeof devicePlatforms)[number];

export const conversationTypes = ['direct'] as const;
export type ConversationType = (typeof conversationTypes)[number];

export const messageTypes = ['text', 'image', 'file', 'system'] as const;
export type MessageType = (typeof messageTypes)[number];

export const attachmentUploadStatuses = ['pending', 'uploaded', 'failed'] as const;
export type AttachmentUploadStatus = (typeof attachmentUploadStatuses)[number];

export const transferSessionStatuses = ['pending', 'approved', 'completed', 'expired'] as const;
export type TransferSessionStatus = (typeof transferSessionStatuses)[number];
