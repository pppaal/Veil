import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { AppConfigService } from '../src/common/config/app-config.service';
import { EphemeralStoreService } from '../src/common/ephemeral-store.service';
import { MockDeviceAuthVerifier } from '../src/modules/auth/device-auth-verifier';
import { PrismaService } from '../src/common/prisma.service';
import { RealtimeGateway } from '../src/modules/realtime/realtime.gateway';
import { FakePrismaService } from './support/fake-prisma.service';
import {
  FakeConfigService,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
} from './support/fake-services';

describe('VEIL API (e2e)', () => {
  let app: INestApplication;
  let prisma: FakePrismaService;
  let verifier: MockDeviceAuthVerifier;

  beforeEach(async () => {
    process.env.VEIL_DATABASE_URL = 'postgresql://veil:veil@localhost:5432/veil';
    process.env.VEIL_S3_ENDPOINT = 'http://localhost:9000';
    process.env.VEIL_S3_REGION = 'us-east-1';
    process.env.VEIL_S3_ACCESS_KEY = 'minioadmin';
    process.env.VEIL_S3_SECRET_KEY = 'minioadmin';
    process.env.VEIL_S3_BUCKET = 'veil-encrypted';

    prisma = new FakePrismaService();
    const { AppModule } = await import('../src/app.module');
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(PrismaService)
      .useValue(prisma)
      .overrideProvider(EphemeralStoreService)
      .useValue(new FakeEphemeralStoreService())
      .overrideProvider(AppConfigService)
      .useValue(new FakeConfigService())
      .overrideProvider(RealtimeGateway)
      .useValue(new FakeRealtimeGateway())
      .compile();

    verifier = moduleRef.get(MockDeviceAuthVerifier);
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    await app.init();
  });

  afterEach(async () => {
    if (app) {
      await app.close();
    }
  });

  it('exposes a public health endpoint', async () => {
    const api = request(app.getHttpServer());

    const health = await api.get('/v1/health');
    expect(health.status).toBe(200);
    expect(health.body).toEqual({
      status: 'ok',
      service: 'veil-api',
    });
  });

  it('covers registration, conversations, messages, attachments, and device transfer', async () => {
    const api = request(app.getHttpServer());

    const registerA = await api.post('/v1/auth/register').send({
      handle: 'icarus',
      displayName: 'Icarus',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-a',
      signedPrekeyBundle: 'prekey-a',
      authPublicKey: 'auth-a',
    });
    expect(registerA.status).toBe(201);

    const registerB = await api.post('/v1/auth/register').send({
      handle: 'selene',
      displayName: 'Selene',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-b',
      signedPrekeyBundle: 'prekey-b',
      authPublicKey: 'auth-b',
    });
    expect(registerB.status).toBe(201);

    const challenge = await api.post('/v1/auth/challenge').send({
      handle: 'icarus',
      deviceId: registerA.body.deviceId,
    });
    const signature = verifier.createProofForDev({
      challenge: challenge.body.challenge,
      authPublicKey: 'auth-a',
      deviceId: registerA.body.deviceId,
    });
    const verify = await api.post('/v1/auth/verify').send({
      challengeId: challenge.body.challengeId,
      deviceId: registerA.body.deviceId,
      signature,
    });
    const bearer = `Bearer ${verify.body.accessToken}`;

    const keyBundle = await api.get('/v1/users/icarus/key-bundle');
    expect(keyBundle.status).toBe(200);
    expect(keyBundle.body.bundle.identityPublicKey).toBe('pub-a');
    expect(keyBundle.body.bundle.authPublicKey).toBeUndefined();

    const conversation = await api
      .post('/v1/conversations/direct')
      .set('Authorization', bearer)
      .send({ peerHandle: 'selene' });
    expect(conversation.status).toBe(201);

    const upload = await api
      .post('/v1/attachments/upload-ticket')
      .set('Authorization', bearer)
      .send({ contentType: 'image/png', sizeBytes: 2048, sha256: 'blob-hash' });
    expect(upload.status).toBe(201);

    await api
      .post('/v1/attachments/complete')
      .set('Authorization', bearer)
      .send({ attachmentId: upload.body.attachmentId, uploadStatus: 'uploaded' })
      .expect(201);

    const send = await api
      .post('/v1/messages')
      .set('Authorization', bearer)
      .send({
        conversationId: conversation.body.conversation.id,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conversation.body.conversation.id,
          senderDeviceId: registerA.body.deviceId,
          recipientUserId: registerB.body.userId,
          ciphertext: 'ZW5jcnlwdGVk',
          nonce: 'nonce-a',
          messageType: 'text',
          attachment: {
            attachmentId: upload.body.attachmentId,
            storageKey: 'attachments/mock/blob',
            contentType: 'image/png',
            sizeBytes: 2048,
            sha256: 'blob-hash',
            encryption: {
              encryptedKey: 'wrapped-key',
              nonce: 'attachment-nonce',
              algorithmHint: 'dev-wrap',
            },
          },
        },
      });
    expect(send.status).toBe(201);

    const listed = await api
      .get(`/v1/conversations/${conversation.body.conversation.id}/messages`)
      .set('Authorization', bearer);
    expect(listed.status).toBe(200);
    expect(listed.body.items).toHaveLength(1);

    const transferInit = await api
      .post('/v1/device-transfer/init')
      .set('Authorization', bearer)
      .send({ oldDeviceId: registerA.body.deviceId });
    expect(transferInit.status).toBe(201);

    await api
      .post('/v1/device-transfer/approve')
      .set('Authorization', bearer)
      .send({
        sessionId: transferInit.body.sessionId,
        newDeviceName: 'Pixel Fold',
        platform: 'android',
        publicIdentityKey: 'pub-new',
        signedPrekeyBundle: 'prekey-new',
        authPublicKey: 'auth-new',
      })
      .expect(201);

    const transferComplete = await api.post('/v1/device-transfer/complete').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
    });
    expect(transferComplete.status).toBe(201);

    const oldBearerAfterTransfer = await api
      .get('/v1/conversations')
      .set('Authorization', bearer);
    expect(oldBearerAfterTransfer.status).toBe(401);
  });

  it('blocks unrelated attachment download tickets and invalidates revoked device tokens', async () => {
    const api = request(app.getHttpServer());

    const registerA = await api.post('/v1/auth/register').send({
      handle: 'atlas',
      displayName: 'Atlas',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-a',
      signedPrekeyBundle: 'prekey-a',
      authPublicKey: 'auth-a',
    });
    expect(registerA.status).toBe(201);

    const registerB = await api.post('/v1/auth/register').send({
      handle: 'outsider',
      displayName: 'Outsider',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-b',
      signedPrekeyBundle: 'prekey-b',
      authPublicKey: 'auth-b',
    });
    expect(registerB.status).toBe(201);

    const challengeA = await api.post('/v1/auth/challenge').send({
      handle: 'atlas',
      deviceId: registerA.body.deviceId,
    });
    const signatureA = verifier.createProofForDev({
      challenge: challengeA.body.challenge,
      authPublicKey: 'auth-a',
      deviceId: registerA.body.deviceId,
    });
    const verifyA = await api.post('/v1/auth/verify').send({
      challengeId: challengeA.body.challengeId,
      deviceId: registerA.body.deviceId,
      signature: signatureA,
    });
    const bearerA = `Bearer ${verifyA.body.accessToken}`;

    const challengeB = await api.post('/v1/auth/challenge').send({
      handle: 'outsider',
      deviceId: registerB.body.deviceId,
    });
    const signatureB = verifier.createProofForDev({
      challenge: challengeB.body.challenge,
      authPublicKey: 'auth-b',
      deviceId: registerB.body.deviceId,
    });
    const verifyB = await api.post('/v1/auth/verify').send({
      challengeId: challengeB.body.challengeId,
      deviceId: registerB.body.deviceId,
      signature: signatureB,
    });
    const bearerB = `Bearer ${verifyB.body.accessToken}`;

    const upload = await api
      .post('/v1/attachments/upload-ticket')
      .set('Authorization', bearerA)
      .send({ contentType: 'application/octet-stream', sizeBytes: 1024, sha256: 'atlas-hash' });
    expect(upload.status).toBe(201);

    const deniedDownload = await api
      .get(`/v1/attachments/${upload.body.attachmentId}/download-ticket`)
      .set('Authorization', bearerB);
    expect(deniedDownload.status).toBe(403);

    const revoked = await api
      .post('/v1/devices/revoke')
      .set('Authorization', bearerA)
      .send({ deviceId: registerA.body.deviceId });
    expect(revoked.status).toBe(201);

    const revokedBearer = await api
      .get('/v1/conversations')
      .set('Authorization', bearerA);
    expect(revokedBearer.status).toBe(401);
  });
});
