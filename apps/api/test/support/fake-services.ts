export class FakeEphemeralStoreService {
  private readonly values = new Map<string, string>();

  async setJson<T>(key: string, value: T): Promise<void> {
    this.values.set(key, JSON.stringify(value));
  }

  async getJson<T>(key: string): Promise<T | null> {
    const value = this.values.get(key);
    return value ? (JSON.parse(value) as T) : null;
  }

  async delete(key: string): Promise<void> {
    this.values.delete(key);
  }
}

export class FakeConfigService {
  port = 3000;
  jwtSecret = 'test-secret';
  jwtAudience = 'veil-mobile';
  jwtIssuer = 'veil-api';
  redisUrl: string | undefined = undefined;
  transferTokenTtlSeconds = 300;
  authChallengeTtlSeconds = 120;
  s3Endpoint = 'http://localhost:9000';
  s3PublicEndpoint = 'http://localhost:9000';
  s3Region = 'us-east-1';
  s3AccessKey = 'minioadmin';
  s3SecretKey = 'minioadmin';
  s3Bucket = 'veil-encrypted';
}

export class FakeRealtimeGateway {
  readonly emitted: Array<{ userId: string; event: string; payload: unknown }> = [];
  readonly connectedUsers = new Set<string>();

  emitToUser(userId: string, event: string, payload: unknown): void {
    this.emitted.push({ userId, event, payload });
  }

  emitConversationMembers(
    members: Array<{ userId: string }>,
    event: string,
    payload: unknown,
  ): void {
    for (const member of members) {
      this.emitted.push({ userId: member.userId, event, payload });
    }
  }

  hasConnectedUser(userId: string): boolean {
    return this.connectedUsers.has(userId);
  }
}

export class FakePushService {
  readonly sentHints: Array<{ pushToken: string; hint: unknown }> = [];

  async sendMessageHint(pushToken: string, hint: unknown): Promise<void> {
    this.sentHints.push({ pushToken, hint });
  }
}

export class FakeAttachmentStorageGateway {
  readonly uploaded = new Map<
    string,
    {
      sizeBytes: number;
      contentType: string;
      metadata: Record<string, string>;
    }
  >();

  async createUploadTarget(storageKey: string, metadata: {
    attachmentId: string;
    sha256: string;
    sizeBytes: number;
    contentType: string;
  }): Promise<{ url: string; headers: Record<string, string>; expiresAt: string }> {
    return {
      url: `https://signed-upload.invalid/${storageKey}`,
      headers: {
        'Content-Type': metadata.contentType,
        'x-amz-meta-encrypted': 'true',
        'x-amz-meta-sha256': metadata.sha256,
        'x-amz-meta-attachment-id': metadata.attachmentId,
      },
      expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    };
  }

  recordUploaded(
    storageKey: string,
    options: {
      sizeBytes: number;
      contentType: string;
      metadata: Record<string, string>;
    },
  ): void {
    this.uploaded.set(storageKey, options);
  }

  async headObject(storageKey: string): Promise<{
    exists: boolean;
    sizeBytes?: number;
    contentType?: string;
    metadata?: Record<string, string>;
  }> {
    const uploaded = this.uploaded.get(storageKey);
    if (!uploaded) {
      return { exists: false };
    }

    return {
      exists: true,
      sizeBytes: uploaded.sizeBytes,
      contentType: uploaded.contentType,
      metadata: uploaded.metadata,
    };
  }

  async createDownloadTarget(storageKey: string): Promise<{ url: string; expiresAt: string }> {
    return {
      url: `https://signed-download.invalid/${storageKey}`,
      expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    };
  }
}
