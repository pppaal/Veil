export interface MessagePushHint {
  kind: 'message.new';
  messageId: string;
  conversationId: string;
  senderDeviceId: string;
  serverReceivedAt: string;
}

export type PushProviderKind = 'none' | 'apns' | 'fcm';

export interface PushProvider {
  readonly kind: PushProviderKind;

  sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void>;
}
