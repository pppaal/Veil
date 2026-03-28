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
  mockAuthSharedSecret = 'test-device-auth-secret';
  redisUrl: string | undefined = undefined;
  transferTokenTtlSeconds = 300;
  authChallengeTtlSeconds = 120;
  s3Endpoint = 'http://localhost:9000';
  s3Bucket = 'veil-encrypted';
}

export class FakeRealtimeGateway {
  readonly emitted: Array<{ userId: string; event: string; payload: unknown }> = [];

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
}
