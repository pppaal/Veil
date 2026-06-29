export interface MessagePushHint {
  kind: 'wake';
}

export type PushProviderKind = 'none' | 'apns' | 'fcm' | 'unifiedpush';

export interface PushProvider {
  readonly kind: PushProviderKind;

  sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void>;
}
