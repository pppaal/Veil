export interface MessagePushHint {
  kind: 'wake';
}

export type PushProviderKind = 'none' | 'apns' | 'fcm' | 'unifiedpush';

export interface PushProvider {
  readonly kind: PushProviderKind;

  sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void>;
}

// The longest one wake may take, connection included. Wakes run after the
// message is relayed, so this bounds the work a stalled provider can pile up,
// not anyone's wait.
export const PUSH_DELIVERY_TIMEOUT_MS = 10_000;
