import { randomUUID } from 'node:crypto';

import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { AppConfigService } from '../../src/common/config/app-config.service';
import { EphemeralStoreService } from '../../src/common/ephemeral-store.service';
import { ApiExceptionFilter } from '../../src/common/filters/api-exception.filter';
import { AppLoggerService } from '../../src/common/logger/app-logger.service';
import { ActorRefGenerator } from '../../src/common/logger/request-redactor';
import { PrismaService } from '../../src/common/prisma.service';
import { ATTACHMENT_STORAGE_GATEWAY } from '../../src/modules/attachments/attachment-storage.gateway';
import { RealtimeGateway } from '../../src/modules/realtime/realtime.gateway';
import { DeviceAuthTestHelper } from '../support/device-auth-test-helper';
import { RetentionFakePrismaService } from '../support/fake-prisma-retention';
import {
  FakeAttachmentStorageGateway,
  FakeConfigService,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
} from '../support/fake-services';

// Drives the real HTTP surface (AppModule, global pipes and filter) to prove
// the server neither stores nor returns plaintext user content.

// Response keys that would carry user-written plaintext.
const PLAINTEXT_KEYS = [
  'displayName',
  'nickname',
  'emoji',
  'avatarPath',
  'bio',
  'statusMessage',
  'statusEmoji',
  'caption',
  'contentUrl',
  'note',
];

const keysOf = (value: unknown): string[] => {
  if (Array.isArray(value)) return value.flatMap(keysOf);
  if (value && typeof value === 'object') {
    return Object.entries(value).flatMap(([key, nested]) => [key, ...keysOf(nested)]);
  }
  return [];
};

const REQUIRED_ENV = {
  VEIL_DATABASE_URL: 'postgresql://veil:veil@localhost:5432/veil',
  VEIL_JWT_SECRET: 'plaintext-free-secret-0123456789abcdef',
  VEIL_S3_ENDPOINT: 'http://localhost:9000',
  VEIL_S3_REGION: 'us-east-1',
  VEIL_S3_ACCESS_KEY: 'minioadmin',
  VEIL_S3_SECRET_KEY: 'minioadmin',
  VEIL_S3_BUCKET: 'veil-encrypted',
};

describe('plaintext-free API', () => {
  let app: INestApplication;
  let prisma: RetentionFakePrismaService;
  const keys = new DeviceAuthTestHelper();

  beforeAll(async () => {
    Object.assign(process.env, REQUIRED_ENV);
    prisma = new RetentionFakePrismaService();
    const { AppModule } = await import('../../src/app.module');
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue(prisma)
      .overrideProvider(EphemeralStoreService)
      .useValue(new FakeEphemeralStoreService())
      .overrideProvider(AppConfigService)
      .useValue(new FakeConfigService())
      .overrideProvider(ATTACHMENT_STORAGE_GATEWAY)
      .useValue(new FakeAttachmentStorageGateway())
      .overrideProvider(RealtimeGateway)
      .useValue(new FakeRealtimeGateway())
      .compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
    );
    app.useGlobalFilters(
      new ApiExceptionFilter(moduleRef.get(AppLoggerService), moduleRef.get(ActorRefGenerator)),
    );
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  const api = () => request(app.getHttpServer());

  // Registers with the plaintext fields older clients still send, then signs in.
  const signUp = async (handle: string) => {
    const keyPair = keys.createKeyPair();
    const registered = await api()
      .post('/v1/auth/register')
      .send({
        handle,
        displayName: `${handle} the Great`,
        deviceName: 'Test phone',
        platform: 'android',
        publicIdentityKey: `ik-${handle}`,
        signedPrekeyBundle: `spk-${handle}`,
        authPublicKey: keyPair.authPublicKey,
      })
      .expect(201);
    const challenge = await api()
      .post('/v1/auth/challenge')
      .send({ handle, deviceId: registered.body.deviceId })
      .expect(201);
    const verified = await api()
      .post('/v1/auth/verify')
      .send({
        challengeId: challenge.body.challengeId,
        deviceId: registered.body.deviceId,
        signature: keys.createProof({
          challenge: challenge.body.challenge,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      })
      .expect(201);
    return {
      userId: registered.body.userId as string,
      deviceId: registered.body.deviceId as string,
      registered: registered.body as unknown,
      bearer: `Bearer ${verified.body.accessToken}`,
    };
  };

  const sendMessage = (
    sender: { deviceId: string; bearer: string },
    conversationId: string,
    recipientUserId: string,
    messageType: string,
  ) =>
    api()
      .post('/v1/messages')
      .set('Authorization', sender.bearer)
      .send({
        conversationId,
        clientMessageId: `client-${randomUUID()}`,
        envelope: {
          version: 'veil-envelope-v2',
          conversationId,
          senderDeviceId: sender.deviceId,
          recipientUserId,
          ciphertext: 'opaque-ciphertext',
          nonce: 'opaque-nonce',
          messageType,
        },
      });

  it('POST /messages/:id/reactions 410 reactions_e2e_only', async () => {
    const alice = await signUp('rho');
    const messageId = randomUUID();

    const added = await api()
      .post(`/v1/messages/${messageId}/reactions`)
      .set('Authorization', alice.bearer)
      .send({ emoji: '👍' });
    const removed = await api()
      .delete(`/v1/messages/${messageId}/reactions`)
      .set('Authorization', alice.bearer);

    for (const response of [added, removed]) {
      expect(response.status).toBe(410);
      expect(response.body.code).toBe('reactions_e2e_only');
    }
  });

  it('profile PATCH 410', async () => {
    const alice = await signUp('sigma');

    const patched = await api()
      .patch('/v1/profile')
      .set('Authorization', alice.bearer)
      .send({ displayName: 'Sigma', bio: 'secret bio' });

    expect(patched.status).toBe(410);
    expect(patched.body.code).toBe('profile_e2e_pending');
    expect(JSON.stringify(prisma.users)).not.toContain('secret bio');
  });

  it('key-bundle route no longer exists', async () => {
    const alice = await signUp('tau');
    const bob = await signUp('upsilon');

    const anonymous = await api().get('/v1/users/upsilon/key-bundle');
    const authenticated = await api()
      .get('/v1/users/upsilon/key-bundle')
      .set('Authorization', alice.bearer);
    expect(anonymous.status).toBe(404);
    expect(authenticated.status).toBe(404);

    const directory = await api().get('/v1/keys/upsilon?claim=none');
    expect(directory.status).toBe(401);
    const signedIn = await api()
      .get('/v1/keys/upsilon?claim=none')
      .set('Authorization', alice.bearer)
      .expect(200);
    expect(signedIn.body.devices.map((device: { deviceId: string }) => device.deviceId)).toEqual([
      bob.deviceId,
    ]);
  });

  it('no response contains displayName, nickname, emoji or avatarPath', async () => {
    const alice = await signUp('alice');
    const bob = await signUp('bob');
    const carol = await signUp('carol');
    const responses: Array<{ route: string; body: unknown }> = [
      { route: 'POST /auth/register', body: alice.registered },
    ];
    const record = async (route: string, pending: request.Test) => {
      const response = await pending;
      if (response.status >= 400) {
        throw new Error(`${route} answered ${response.status}: ${JSON.stringify(response.body)}`);
      }
      responses.push({ route, body: response.body as unknown });
      return response.body;
    };
    const as = (user: { bearer: string }) => ({
      get: (path: string) => api().get(`/v1${path}`).set('Authorization', user.bearer),
      post: (path: string, body: object = {}) =>
        api().post(`/v1${path}`).set('Authorization', user.bearer).send(body),
    });

    await record('GET /profile', as(alice).get('/profile'));
    await record('GET /users/:handle', as(alice).get('/users/bob'));
    await record('GET /keys/:handle', as(alice).get('/keys/bob?claim=none'));
    await record('POST /contacts', as(alice).post('/contacts', { handle: 'bob', nickname: 'Mom' }));
    await record('POST /contacts', as(bob).post('/contacts', { handle: 'alice' }));
    await record('GET /contacts', as(alice).get('/contacts'));

    const direct = await record(
      'POST /conversations/direct',
      as(alice).post('/conversations/direct', { peerHandle: 'bob' }),
    );
    const conversationId = direct.conversation.id as string;
    await record('POST /messages', sendMessage(alice, conversationId, bob.userId, 'text'));
    await record('POST /messages', sendMessage(bob, conversationId, alice.userId, 'reaction'));
    await record('GET /conversations', as(alice).get('/conversations'));
    await record(
      'GET /conversations/:id/messages',
      as(bob).get(`/conversations/${conversationId}/messages`),
    );

    const group = await record(
      'POST /conversations/group',
      as(alice).post('/conversations/group', { name: 'Hikers', memberHandles: ['bob'] }),
    );
    await record('GET /conversations/group/:id', as(bob).get(`/conversations/group/${group.id}`));
    const channel = await record(
      'POST /conversations/channel',
      as(alice).post('/conversations/channel', { name: 'News' }),
    );
    await record(
      'GET /conversations/channel/:id',
      as(alice).get(`/conversations/channel/${channel.id}`),
    );

    await record('POST /safety/blocks', as(alice).post('/safety/blocks', { userId: carol.userId }));
    await record('GET /safety/blocks', as(alice).get('/safety/blocks'));
    await record(
      'POST /safety/reports',
      as(alice).post('/safety/reports', {
        reportedUserId: carol.userId,
        reason: 'spam',
        note: 'free text the server must drop',
      }),
    );

    await record(
      'POST /stories',
      as(alice).post('/stories', {
        ciphertext: 'sealed-story',
        envelopeVersion: 'veil-envelope-v2',
        audienceUserIds: [bob.userId],
      }),
    );
    await record('GET /stories', as(bob).get('/stories'));
    await record('GET /devices', as(alice).get('/devices'));

    const leaked = responses.flatMap(({ route, body }) =>
      keysOf(body)
        .filter((key) => PLAINTEXT_KEYS.includes(key))
        .map((key) => `${route}: ${key}`),
    );
    expect(leaked).toEqual([]);
    expect(responses.length).toBeGreaterThan(20);

    // Nothing the clients sent as plaintext reached a stored row either.
    const stored = JSON.stringify({
      users: prisma.users,
      contacts: prisma.userContacts,
      reports: prisma.abuseReports,
      messages: prisma.messages,
    });
    for (const plaintext of ['the Great', 'Mom', 'free text the server must drop']) {
      expect(stored).not.toContain(plaintext);
    }
  });
});
