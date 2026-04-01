import { Injectable } from '@nestjs/common';

export interface MessagePushHint {
  kind: 'message.new';
  messageId: string;
  conversationId: string;
  senderDeviceId: string;
  serverReceivedAt: string;
}

@Injectable()
export class PushService {
  async sendMessageHint(
    pushToken: string,
    hint: MessagePushHint,
  ): Promise<void> {
    void pushToken;
    void hint;
    // Intentionally metadata-only. Real APNs/FCM integration belongs behind this seam.
  }
}
