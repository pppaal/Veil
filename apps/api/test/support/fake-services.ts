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
  trustProxy = false;
  swaggerEnabled = true;
  allowedOrigins = ['http://localhost:3000', 'http://127.0.0.1:3000'];
  transferTokenTtlSeconds = 300;
  authChallengeTtlSeconds = 120;
  s3Endpoint = 'http://localhost:9000';
  s3PublicEndpoint = 'http://localhost:9000';
  s3Region = 'us-east-1';
  s3AccessKey = 'minioadmin';
  s3SecretKey = 'minioadmin';
  s3Bucket = 'veil-encrypted';
  attachmentMaxBytes = 50 * 1024 * 1024;
  attachmentAllowedMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/octet-stream',
  ];

  isOriginAllowed(origin?: string | null): boolean {
    if (!origin) {
      return true;
    }
    return this.allowedOrigins.includes(origin);
  }
}

export class FakeRealtimeGateway {
  readonly emitted: Array<{ userId: string; event: string; payload: unknown }> = [];
  readonly connectedUsers = new Set<string>();
  readonly connectedDevices = new Set<string>();
  readonly disconnectedDevices = new Set<string>();

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

  hasConnectedDevice(deviceId: string): boolean {
    return this.connectedDevices.has(deviceId);
  }

  connectedDeviceIdsForUser(userId: string): string[] {
    return this.connectedUsers.has(userId) ? [...this.connectedDevices] : [];
  }

  disconnectDevice(deviceId: string): void {
    this.disconnectedDevices.add(deviceId);
  }
}

export class FakePushService {
  readonly providerKind = 'none' as const;
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
  }): Promise<{ url: string; headers: Record<string, string>; contentType: string; sizeBytes: number; expiresAt: string }> {
    return {
      url: `https://signed-upload.invalid/${storageKey}`,
      headers: {
        'Content-Type': metadata.contentType,
        'Content-Length': String(metadata.sizeBytes),
        'Cache-Control': 'no-store',
        'x-amz-meta-encrypted': 'true',
        'x-amz-meta-sha256': metadata.sha256,
        'x-amz-meta-attachment-id': metadata.attachmentId,
      },
      contentType: metadata.contentType,
      sizeBytes: metadata.sizeBytes,
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

  async deleteObject(storageKey: string): Promise<void> {
    this.uploaded.delete(storageKey);
  }
}
