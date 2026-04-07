import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { AppConfigService } from '../src/common/config/app-config.service';
import { ApiExceptionFilter } from '../src/common/filters/api-exception.filter';
import { AppLoggerService } from '../src/common/logger/app-logger.service';
import { EphemeralStoreService } from '../src/common/ephemeral-store.service';
import { Ed25519DeviceAuthVerifier } from '../src/modules/auth/device-auth-verifier';
import { ATTACHMENT_STORAGE_GATEWAY } from '../src/modules/attachments/attachment-storage.gateway';
import { PrismaService } from '../src/common/prisma.service';
import { RealtimeGateway } from '../src/modules/realtime/realtime.gateway';
import { DeviceAuthTestHelper } from './support/device-auth-test-helper';
import { FakePrismaService } from './support/fake-prisma.service';
import {
  FakeAttachmentStorageGateway,
  FakeConfigService,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
} from './support/fake-services';

jest.setTimeout(240000);

describe('VEIL API (e2e)', () => {
  let app: INestApplication;
  let prisma: FakePrismaService;
  let verifier: Ed25519DeviceAuthVerifier;
  let keyHelper: DeviceAuthTestHelper;
  let realtime: FakeRealtimeGateway;
  let attachmentStorage: FakeAttachmentStorageGateway;

  beforeEach(async () => {
    process.env.VEIL_DATABASE_URL = 'postgresql://veil:veil@localhost:5432/veil';
    process.env.VEIL_S3_ENDPOINT = 'http://localhost:9000';
    process.env.VEIL_S3_REGION = 'us-east-1';
    process.env.VEIL_S3_ACCESS_KEY = 'minioadmin';
    process.env.VEIL_S3_SECRET_KEY = 'minioadmin';
    process.env.VEIL_S3_BUCKET = 'veil-encrypted';

    prisma = new FakePrismaService();
    realtime = new FakeRealtimeGateway();
    attachmentStorage = new FakeAttachmentStorageGateway();
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
      .overrideProvider(ATTACHMENT_STORAGE_GATEWAY)
      .useValue(attachmentStorage)
      .overrideProvider(RealtimeGateway)
      .useValue(realtime)
      .compile();

    verifier = moduleRef.get(Ed25519DeviceAuthVerifier);
    keyHelper = new DeviceAuthTestHelper();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    app.useGlobalFilters(new ApiExceptionFilter(moduleRef.get(AppLoggerService)));
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

    const readiness = await api.get('/v1/health/ready');
    expect(readiness.status).toBe(200);
    expect(readiness.body.status).toBe('ok');
    expect(readiness.body.checks.allowedOriginsConfigured).toBe(true);
    expect(readiness.body.checks.productionBootBlocked).toBe(true);

    const missingBundle = await api.get('/v1/users/unknown/key-bundle');
    expect(missingBundle.status).toBe(404);
    expect(missingBundle.body.code).toBe('active_device_not_found');
  });

  it('covers registration, conversations, messages, attachments, and device transfer', async () => {
    const api = request(app.getHttpServer());
    const keyPairA = keyHelper.createKeyPair();
    const keyPairB = keyHelper.createKeyPair();
    const transferKeyPair = keyHelper.createKeyPair();

    const registerA = await api.post('/v1/auth/register').send({
      handle: 'icarus',
      displayName: 'Icarus',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-a',
      signedPrekeyBundle: 'prekey-a',
      authPublicKey: keyPairA.authPublicKey,
    });
    expect(registerA.status).toBe(201);

    const registerB = await api.post('/v1/auth/register').send({
      handle: 'selene',
      displayName: 'Selene',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-b',
      signedPrekeyBundle: 'prekey-b',
      authPublicKey: keyPairB.authPublicKey,
    });
    expect(registerB.status).toBe(201);

    const challenge = await api.post('/v1/auth/challenge').send({
      handle: 'icarus',
      deviceId: registerA.body.deviceId,
    });
    const signature = keyHelper.createProof({
      challenge: challenge.body.challenge,
      authPrivateKey: keyPairA.authPrivateKey,
    });
    const verify = await api.post('/v1/auth/verify').send({
      challengeId: challenge.body.challengeId,
      deviceId: registerA.body.deviceId,
      signature,
    });
    const bearer = `Bearer ${verify.body.accessToken}`;

    const initialDevices = await api
      .get('/v1/devices')
      .set('Authorization', bearer);
    expect(initialDevices.status).toBe(200);
    expect(initialDevices.body.activeDeviceId).toBe(registerA.body.deviceId);
    expect(initialDevices.body.items).toHaveLength(1);
    expect(initialDevices.body.items[0].deviceName).toBe('VEIL Desktop');
    expect(initialDevices.body.items[0].trustState).toBe('current');

    const keyBundle = await api.get('/v1/users/icarus/key-bundle');
    expect(keyBundle.status).toBe(200);
    expect(keyBundle.body.bundle.identityPublicKey).toBe('pub-a');
    expect(Array.isArray(keyBundle.body.deviceBundles)).toBe(true);
    expect(keyBundle.body.deviceBundles.length).toBeGreaterThan(0);
    expect(keyBundle.body.deviceBundles[0].deviceId).toBeDefined();
    expect(keyBundle.body.bundle.authPublicKey).toBeUndefined();

    const conversation = await api
      .post('/v1/conversations/direct')
      .set('Authorization', bearer)
      .send({ peerHandle: 'selene' });
    expect(conversation.status).toBe(201);

    const upload = await api
      .post('/v1/attachments/upload-ticket')
      .set('Authorization', bearer)
      .send({ contentType: 'image/png', sizeBytes: 2048, sha256: 'abcdef1234567890' });
    expect(upload.status).toBe(201);
    attachmentStorage.recordUploaded(upload.body.upload.storageKey, {
      sizeBytes: 2048,
      contentType: 'image/png',
      metadata: {
        encrypted: 'true',
        sha256: 'abcdef1234567890',
        'attachment-id': upload.body.attachmentId,
      },
    });

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
        clientMessageId: 'client-msg-001',
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
            sha256: 'abcdef1234567890',
            encryption: {
              encryptedKey: 'wrapped-key',
              nonce: 'attachment-nonce',
              algorithmHint: 'dev-wrap',
            },
          },
        },
      });
    expect(send.status).toBe(201);
    expect(send.body.idempotent).toBe(false);
    expect(send.body.message.clientMessageId).toBe('client-msg-001');
    expect(send.body.message.conversationOrder).toBe(1);

    const duplicateSend = await api
      .post('/v1/messages')
      .set('Authorization', bearer)
      .send({
        conversationId: conversation.body.conversation.id,
        clientMessageId: 'client-msg-001',
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conversation.body.conversation.id,
          senderDeviceId: registerA.body.deviceId,
          recipientUserId: registerB.body.userId,
          ciphertext: 'ZW5jcnlwdGVk',
          nonce: 'nonce-a',
          messageType: 'text',
        },
      });
    expect(duplicateSend.status).toBe(201);
    expect(duplicateSend.body.idempotent).toBe(true);
    expect(duplicateSend.body.message.id).toBe(send.body.message.id);

    const listed = await api
      .get(`/v1/conversations/${conversation.body.conversation.id}/messages`)
      .set('Authorization', bearer);
    expect(listed.status).toBe(200);
    expect(listed.body.items).toHaveLength(1);
    expect(listed.body.items[0].clientMessageId).toBe('client-msg-001');

    const transferInit = await api
      .post('/v1/device-transfer/init')
      .set('Authorization', bearer)
      .send({ oldDeviceId: registerA.body.deviceId });
    expect(transferInit.status).toBe(201);

    const transferClaim = await api.post('/v1/device-transfer/claim').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
      newDeviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-new',
      signedPrekeyBundle: 'prekey-new',
      authPublicKey: transferKeyPair.authPublicKey,
      authProof: keyHelper.createProof({
        challenge: `transfer-claim:${transferInit.body.sessionId}:${transferInit.body.transferToken}`,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });
    expect(transferClaim.status).toBe(201);

    await api
      .post('/v1/device-transfer/approve')
      .set('Authorization', bearer)
      .send({
        sessionId: transferInit.body.sessionId,
        claimId: transferClaim.body.claimId,
      })
      .expect(201);

    const transferComplete = await api.post('/v1/device-transfer/complete').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
      claimId: transferClaim.body.claimId,
      authProof: keyHelper.createProof({
        challenge: `transfer-complete:${transferInit.body.sessionId}:${transferClaim.body.claimId}:${transferInit.body.transferToken}`,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });
    expect(transferComplete.status).toBe(201);
    expect(transferComplete.body.handle).toBe('icarus');
    expect(transferComplete.body.displayName).toBe('Icarus');

    const replayedTransferComplete = await api.post('/v1/device-transfer/complete').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
      claimId: transferClaim.body.claimId,
      authProof: keyHelper.createProof({
        challenge: `transfer-complete:${transferInit.body.sessionId}:${transferClaim.body.claimId}:${transferInit.body.transferToken}`,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });
    expect(replayedTransferComplete.status).toBe(403);
    expect(replayedTransferComplete.body.code).toBe('transfer_session_inactive');

    const transferredChallenge = await api.post('/v1/auth/challenge').send({
      handle: 'icarus',
      deviceId: transferComplete.body.newDeviceId,
    });
    const transferredVerify = await api.post('/v1/auth/verify').send({
      challengeId: transferredChallenge.body.challengeId,
      deviceId: transferComplete.body.newDeviceId,
      signature: keyHelper.createProof({
        challenge: transferredChallenge.body.challenge,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });
    const transferredBearer = `Bearer ${transferredVerify.body.accessToken}`;

    const devicesAfterTransfer = await api
      .get('/v1/devices')
      .set('Authorization', transferredBearer);
    expect(devicesAfterTransfer.status).toBe(200);
    expect(devicesAfterTransfer.body.activeDeviceId).toBe(transferComplete.body.newDeviceId);
    expect(devicesAfterTransfer.body.items).toHaveLength(2);
    expect(
      devicesAfterTransfer.body.items.some(
        (item: { id: string; isActive: boolean; trustState: string }) =>
          item.id === registerA.body.deviceId && item.isActive === true && item.trustState === 'trusted',
      ),
    ).toBe(true);
    expect(
      devicesAfterTransfer.body.items.some(
        (item: { id: string; joinedFromDeviceId?: string | null; trustState: string }) =>
          item.id === transferComplete.body.newDeviceId &&
          item.joinedFromDeviceId === registerA.body.deviceId &&
          item.trustState === 'current',
      ),
    ).toBe(true);

    const oldBearerAfterTransfer = await api
      .get('/v1/conversations')
      .set('Authorization', bearer);
    expect(oldBearerAfterTransfer.status).toBe(200);

    const foreignInit = await api
      .post('/v1/device-transfer/init')
      .set('Authorization', transferredBearer)
      .send({ oldDeviceId: registerA.body.deviceId });
    expect(foreignInit.status).toBe(403);
    expect(foreignInit.body.code).toBe('device_forbidden');
  });

  it('blocks unrelated attachment download tickets and invalidates revoked device tokens', async () => {
    const api = request(app.getHttpServer());
    const keyPairA = keyHelper.createKeyPair();
    const keyPairB = keyHelper.createKeyPair();

    const registerA = await api.post('/v1/auth/register').send({
      handle: 'atlas',
      displayName: 'Atlas',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-a',
      signedPrekeyBundle: 'prekey-a',
      authPublicKey: keyPairA.authPublicKey,
    });
    expect(registerA.status).toBe(201);

    const registerB = await api.post('/v1/auth/register').send({
      handle: 'outsider',
      displayName: 'Outsider',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-b',
      signedPrekeyBundle: 'prekey-b',
      authPublicKey: keyPairB.authPublicKey,
    });
    expect(registerB.status).toBe(201);

    const challengeA = await api.post('/v1/auth/challenge').send({
      handle: 'atlas',
      deviceId: registerA.body.deviceId,
    });
    const signatureA = keyHelper.createProof({
      challenge: challengeA.body.challenge,
      authPrivateKey: keyPairA.authPrivateKey,
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
    const signatureB = keyHelper.createProof({
      challenge: challengeB.body.challenge,
      authPrivateKey: keyPairB.authPrivateKey,
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
      .send({ contentType: 'application/octet-stream', sizeBytes: 1024, sha256: 'abcdef1234567890' });
    expect(upload.status).toBe(201);
    attachmentStorage.recordUploaded(upload.body.upload.storageKey, {
      sizeBytes: 1024,
      contentType: 'application/octet-stream',
      metadata: {
        encrypted: 'true',
        sha256: 'abcdef1234567890',
        'attachment-id': upload.body.attachmentId,
      },
    });
    await api
      .post('/v1/attachments/complete')
      .set('Authorization', bearerA)
      .send({ attachmentId: upload.body.attachmentId, uploadStatus: 'uploaded' })
      .expect(201);

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
    expect(revokedBearer.body.code).toBe('device_not_active');
  });

  it('rejects disallowed attachment MIME types and cleans up failed upload sessions', async () => {
    const api = request(app.getHttpServer());
    const keyPair = keyHelper.createKeyPair();

    const register = await api.post('/v1/auth/register').send({
      handle: 'attester',
      displayName: 'Attester',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-attester',
      signedPrekeyBundle: 'prekey-attester',
      authPublicKey: keyPair.authPublicKey,
    });

    const challenge = await api.post('/v1/auth/challenge').send({
      handle: 'attester',
      deviceId: register.body.deviceId,
    });
    const verify = await api.post('/v1/auth/verify').send({
      challengeId: challenge.body.challengeId,
      deviceId: register.body.deviceId,
      signature: keyHelper.createProof({
        challenge: challenge.body.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });
    const bearer = `Bearer ${verify.body.accessToken}`;

    const rejectedMime = await api
      .post('/v1/attachments/upload-ticket')
      .set('Authorization', bearer)
      .send({ contentType: 'text/plain', sizeBytes: 128, sha256: 'abcdef12' });
    expect(rejectedMime.status).toBe(400);
    expect(rejectedMime.body.code).toBe('attachment_upload_invalid');

    const upload = await api
      .post('/v1/attachments/upload-ticket')
      .set('Authorization', bearer)
      .send({ contentType: 'application/octet-stream', sizeBytes: 1024, sha256: 'abcdef1234567890' });
    expect(upload.status).toBe(201);

    attachmentStorage.recordUploaded(upload.body.upload.storageKey, {
      sizeBytes: 1024,
      contentType: 'application/octet-stream',
      metadata: {
        encrypted: 'true',
        sha256: 'abcdef1234567890',
        'attachment-id': upload.body.attachmentId,
      },
    });

    const failedComplete = await api
      .post('/v1/attachments/complete')
      .set('Authorization', bearer)
      .send({ attachmentId: upload.body.attachmentId, uploadStatus: 'failed' });
    expect(failedComplete.status).toBe(201);
    expect(attachmentStorage.uploaded.has(upload.body.upload.storageKey)).toBe(false);
  });

  it('returns explicit error codes and rejects transfer completion replay without new-device proof', async () => {
    const api = request(app.getHttpServer());
    const keyPair = keyHelper.createKeyPair();
    const transferKeyPair = keyHelper.createKeyPair();

    const register = await api.post('/v1/auth/register').send({
      handle: 'replaytest',
      displayName: 'Replay Test',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-a',
      signedPrekeyBundle: 'prekey-a',
      authPublicKey: keyPair.authPublicKey,
    });

    const challenge = await api.post('/v1/auth/challenge').send({
      handle: 'replaytest',
      deviceId: register.body.deviceId,
    });

    const invalidVerify = await api.post('/v1/auth/verify').send({
      challengeId: challenge.body.challengeId,
      deviceId: register.body.deviceId,
      signature: keyHelper.createProof({
        challenge: challenge.body.challenge,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });
    expect(invalidVerify.status).toBe(401);
    expect(invalidVerify.body.code).toBe('invalid_device_signature');

    const reusedChallenge = await api.post('/v1/auth/verify').send({
      challengeId: challenge.body.challengeId,
      deviceId: register.body.deviceId,
      signature: keyHelper.createProof({
        challenge: challenge.body.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });
    expect(reusedChallenge.status).toBe(401);
    expect(reusedChallenge.body.code).toBe('challenge_invalid');

    const supersededChallenge = await api.post('/v1/auth/challenge').send({
      handle: 'replaytest',
      deviceId: register.body.deviceId,
    });
    const newestChallenge = await api.post('/v1/auth/challenge').send({
      handle: 'replaytest',
      deviceId: register.body.deviceId,
    });

    const supersededVerify = await api.post('/v1/auth/verify').send({
      challengeId: supersededChallenge.body.challengeId,
      deviceId: register.body.deviceId,
      signature: keyHelper.createProof({
        challenge: supersededChallenge.body.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });
    expect(supersededVerify.status).toBe(401);
    expect(supersededVerify.body.code).toBe('challenge_invalid');

    const verify = await api.post('/v1/auth/verify').send({
      challengeId: newestChallenge.body.challengeId,
      deviceId: register.body.deviceId,
      signature: keyHelper.createProof({
        challenge: newestChallenge.body.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });
    const bearer = `Bearer ${verify.body.accessToken}`;

    const transferInit = await api
      .post('/v1/device-transfer/init')
      .set('Authorization', bearer)
      .send({ oldDeviceId: register.body.deviceId });

    const transferClaim = await api.post('/v1/device-transfer/claim').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
      newDeviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-new',
      signedPrekeyBundle: 'prekey-new',
      authPublicKey: transferKeyPair.authPublicKey,
      authProof: keyHelper.createProof({
        challenge: `transfer-claim:${transferInit.body.sessionId}:${transferInit.body.transferToken}`,
        authPrivateKey: transferKeyPair.authPrivateKey,
      }),
    });

    await api
      .post('/v1/device-transfer/approve')
      .set('Authorization', bearer)
      .send({
        sessionId: transferInit.body.sessionId,
        claimId: transferClaim.body.claimId,
      })
      .expect(201);

    const invalidComplete = await api.post('/v1/device-transfer/complete').send({
      sessionId: transferInit.body.sessionId,
      transferToken: transferInit.body.transferToken,
      claimId: transferClaim.body.claimId,
      authProof: keyHelper.createProof({
        challenge: `transfer-complete:${transferInit.body.sessionId}:${transferClaim.body.claimId}:${transferInit.body.transferToken}`,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });
    expect(invalidComplete.status).toBe(401);
    expect(invalidComplete.body.code).toBe('transfer_completion_invalid');
  });

  it('paginates messages and reconciles delivery/read receipts', async () => {
    const api = request(app.getHttpServer());
    const keyPairA = keyHelper.createKeyPair();
    const keyPairB = keyHelper.createKeyPair();

    const registerA = await api.post('/v1/auth/register').send({
      handle: 'nyx',
      displayName: 'Nyx',
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-nyx',
      signedPrekeyBundle: 'prekey-nyx',
      authPublicKey: keyPairA.authPublicKey,
    });
    const registerB = await api.post('/v1/auth/register').send({
      handle: 'orion',
      displayName: 'Orion',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-orion',
      signedPrekeyBundle: 'prekey-orion',
      authPublicKey: keyPairB.authPublicKey,
    });

    const challengeA = await api.post('/v1/auth/challenge').send({
      handle: 'nyx',
      deviceId: registerA.body.deviceId,
    });
    const verifyA = await api.post('/v1/auth/verify').send({
      challengeId: challengeA.body.challengeId,
      deviceId: registerA.body.deviceId,
      signature: keyHelper.createProof({
        challenge: challengeA.body.challenge,
        authPrivateKey: keyPairA.authPrivateKey,
      }),
    });
    const bearerA = `Bearer ${verifyA.body.accessToken}`;

    const challengeB = await api.post('/v1/auth/challenge').send({
      handle: 'orion',
      deviceId: registerB.body.deviceId,
    });
    const verifyB = await api.post('/v1/auth/verify').send({
      challengeId: challengeB.body.challengeId,
      deviceId: registerB.body.deviceId,
      signature: keyHelper.createProof({
        challenge: challengeB.body.challenge,
        authPrivateKey: keyPairB.authPrivateKey,
      }),
    });
    const bearerB = `Bearer ${verifyB.body.accessToken}`;

    const conversation = await api
      .post('/v1/conversations/direct')
      .set('Authorization', bearerA)
      .send({ peerHandle: 'orion' });

    await api
      .post('/v1/messages')
      .set('Authorization', bearerA)
      .send({
        conversationId: conversation.body.conversation.id,
        clientMessageId: 'client-msg-1001',
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conversation.body.conversation.id,
          senderDeviceId: registerA.body.deviceId,
          recipientUserId: registerB.body.userId,
          ciphertext: 'cipher-1',
          nonce: 'nonce-1',
          messageType: 'text',
        },
      })
      .expect(201);

    const secondSend = await api
      .post('/v1/messages')
      .set('Authorization', bearerA)
      .send({
        conversationId: conversation.body.conversation.id,
        clientMessageId: 'client-msg-1002',
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conversation.body.conversation.id,
          senderDeviceId: registerA.body.deviceId,
          recipientUserId: registerB.body.userId,
          ciphertext: 'cipher-2',
          nonce: 'nonce-2',
          messageType: 'text',
        },
      });
    expect(secondSend.body.message.conversationOrder).toBe(2);

    const firstPage = await api
      .get(`/v1/conversations/${conversation.body.conversation.id}/messages?limit=1`)
      .set('Authorization', bearerB);
    expect(firstPage.status).toBe(200);
    expect(firstPage.body.items).toHaveLength(1);
    expect(firstPage.body.items[0].clientMessageId).toBe('client-msg-1002');
    expect(firstPage.body.items[0].deliveredAt).toBeTruthy();
    expect(firstPage.body.nextCursor).toBeTruthy();

    const secondPage = await api
      .get(
        `/v1/conversations/${conversation.body.conversation.id}/messages?limit=1&cursor=${firstPage.body.nextCursor}`,
      )
      .set('Authorization', bearerB);
    expect(secondPage.status).toBe(200);
    expect(secondPage.body.items).toHaveLength(1);
    expect(secondPage.body.items[0].clientMessageId).toBe('client-msg-1001');

    const markRead = await api
      .post(`/v1/messages/${firstPage.body.items[0].id}/read`)
      .set('Authorization', bearerB)
      .send({});
    expect(markRead.status).toBe(201);
    const emittedReadCountAfterFirstRead = realtime.emitted.filter(
      (event) =>
        event.event === 'message.read' &&
        event.userId === registerA.body.userId,
    ).length;

    const repeatedMarkRead = await api
      .post(`/v1/messages/${firstPage.body.items[0].id}/read`)
      .set('Authorization', bearerB)
      .send({});
    expect(repeatedMarkRead.status).toBe(201);
    expect(
      realtime.emitted.filter(
        (event) =>
          event.event === 'message.read' &&
          event.userId === registerA.body.userId,
      ).length,
    ).toBe(emittedReadCountAfterFirstRead);

    const senderView = await api
      .get(`/v1/conversations/${conversation.body.conversation.id}/messages?limit=2`)
      .set('Authorization', bearerA);
    expect(senderView.status).toBe(200);
    expect(senderView.body.items[1].clientMessageId).toBe('client-msg-1002');
    expect(
      senderView.body.items.some(
        (item: { clientMessageId: string; readAt?: string | null }) =>
          item.clientMessageId == 'client-msg-1002' && item.readAt,
      ),
    ).toBe(true);

    expect(
      realtime.emitted.some(
        (event) => event.event === 'message.delivered' && event.userId === registerA.body.userId,
      ),
    ).toBe(true);
    expect(
      realtime.emitted.some(
        (event) => event.event === 'message.read' && event.userId === registerA.body.userId,
      ),
    ).toBe(true);
  });
});
