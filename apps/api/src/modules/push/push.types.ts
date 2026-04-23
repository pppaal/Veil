export interface MessagePushHint {
  kind: 'wake';
}

export type PushProviderKind = 'none' | 'apns' | 'fcm';

export interface PushProvider {
  readonly kind: PushProviderKind;

  sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void>;
}
