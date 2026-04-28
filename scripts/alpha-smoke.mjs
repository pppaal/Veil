import { createPrivateKey, generateKeyPairSync, sign } from 'node:crypto';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { URL } from 'node:url';
import { io } from 'socket.io-client';

function rawPut(url, headers, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? httpsRequest : httpRequest;
    const req = lib(
      {
        method: 'PUT',
        protocol: u.protocol,
        hostname: u.hostname,
        port: u.port,
        path: `${u.pathname}${u.search}`,
        headers: { ...headers, 'Content-Length': String(body.length) },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () =>
          resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }),
        );
      },
    );
    req.on('error', reject);
    req.end(body);
  });
}

const baseUrl = process.env.VEIL_ALPHA_BASE_URL ?? 'http://127.0.0.1:3000/v1';
const spkiPrefix = Buffer.from('302a300506032b6570032100', 'hex');

function makeKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  return {
    authPublicKey: publicKey
      .export({ format: 'der', type: 'spki' })
      .subarray(spkiPrefix.length)
      .toString('base64url'),
    authPrivateKey: privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64url'),
  };
}

function signChallenge(challenge, authPrivateKey) {
  const key = createPrivateKey({
    key: Buffer.from(authPrivateKey, 'base64url'),
    format: 'der',
    type: 'pkcs8',
  });
  return sign(null, Buffer.from(challenge, 'utf8'), key).toString('base64url');
}

async function requestJson(path, { method = 'GET', body, token } = {}) {
  let response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: {
        ...(body ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  } catch (error) {
    throw new Error(`${path} fetch failed: ${error instanceof Error ? error.message : String(error)}`);
  }

  const text = await response.text();
  const json = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`${path} ${response.status} ${JSON.stringify(json)}`);
  }

  return json;
}

async function waitForApi() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const health = await requestJson('/health');
      if (health.status === 'ok') {
        return;
      }
    } catch {
      // Keep waiting.
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  throw new Error(`API did not become ready at ${baseUrl}`);
}

async function run() {
  await waitForApi();
  const accountA = makeKeyPair();
  const accountB = makeKeyPair();
  const transferDevice = makeKeyPair();
  const suffix = Date.now().toString(36);
  const handleA = `alphaa${suffix}`.slice(0, 18);
  const handleB = `alphab${suffix}`.slice(0, 18);

  const regA = await requestJson('/auth/register', {
    method: 'POST',
    body: {
      handle: handleA,
      displayName: 'Alpha A',
      deviceName: 'Alpha Device A',
      platform: 'android',
      publicIdentityKey: `pub-${suffix}-a`,
      signedPrekeyBundle: `prekey-${suffix}-a`,
      authPublicKey: accountA.authPublicKey,
    },
  });

  const regB = await requestJson('/auth/register', {
    method: 'POST',
    body: {
      handle: handleB,
      displayName: 'Alpha B',
      deviceName: 'Alpha Device B',
      platform: 'ios',
      publicIdentityKey: `pub-${suffix}-b`,
      signedPrekeyBundle: `prekey-${suffix}-b`,
      authPublicKey: accountB.authPublicKey,
    },
  });

  const challengeA = await requestJson('/auth/challenge', {
    method: 'POST',
    body: {
      handle: handleA,
      deviceId: regA.deviceId,
    },
  });

  const verifyA = await requestJson('/auth/verify', {
    method: 'POST',
    body: {
      challengeId: challengeA.challengeId,
      deviceId: regA.deviceId,
      signature: signChallenge(challengeA.challenge, accountA.authPrivateKey),
    },
  });
  const tokenA = verifyA.accessToken;

  // Bob also logs in so we can connect his WS and assert that the realtime
  // gateway fans out message.new when Alice sends. This catches contract
  // drift (renamed events, missing fields) that the REST-only smoke missed.
  const challengeB = await requestJson('/auth/challenge', {
    method: 'POST',
    body: { handle: handleB, deviceId: regB.deviceId },
  });
  const verifyB = await requestJson('/auth/verify', {
    method: 'POST',
    body: {
      challengeId: challengeB.challengeId,
      deviceId: regB.deviceId,
      signature: signChallenge(challengeB.challenge, accountB.authPrivateKey),
    },
  });
  const tokenB = verifyB.accessToken;

  const conversation = await requestJson('/conversations/direct', {
    method: 'POST',
    token: tokenA,
    body: { peerHandle: handleB },
  });

  const upload = await requestJson('/attachments/upload-ticket', {
    method: 'POST',
    token: tokenA,
    body: {
      contentType: 'application/octet-stream',
      sizeBytes: 2048,
      sha256: `deadbeef${suffix.replace(/[^a-fA-F0-9]/g, '0').padEnd(56, '0').slice(0, 56)}`,
    },
  });

  const uploadBody = Buffer.from(Array.from({ length: 2048 }, (_, index) => index % 251));
  const uploadPut = await rawPut(upload.upload.uploadUrl, upload.upload.headers, uploadBody);
  if (uploadPut.status < 200 || uploadPut.status >= 300) {
    throw new Error(`upload PUT ${uploadPut.status} ${uploadPut.body}`);
  }

  const complete = await requestJson('/attachments/complete', {
    method: 'POST',
    token: tokenA,
    body: {
      attachmentId: upload.attachmentId,
      uploadStatus: 'uploaded',
    },
  });

  // Subscribe Bob via WebSocket and remember every message.new that arrives.
  // We assert below that the send fan-out hits the realtime channel.
  const wsUrl = baseUrl.replace(/\/v1$/, '');
  const bobSocket = io(wsUrl, {
    path: '/v1/realtime',
    auth: { token: tokenB },
    transports: ['websocket'],
    forceNew: true,
    reconnection: false,
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Bob WS connect timed out')), 5000);
    bobSocket.once('connect', () => {
      clearTimeout(timer);
      resolve();
    });
    bobSocket.once('connect_error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
  const wsMessages = [];
  bobSocket.on('message.new', (msg) => wsMessages.push(msg));

  const sent = await requestJson('/messages', {
    method: 'POST',
    token: tokenA,
    body: {
      conversationId: conversation.conversation.id,
      clientMessageId: `client-${suffix}`,
      envelope: {
        version: 'veil-envelope-v1-dev',
        conversationId: conversation.conversation.id,
        senderDeviceId: regA.deviceId,
        recipientUserId: regB.userId,
        ciphertext: `opaque-${suffix}`,
        nonce: `nonce-${suffix}`,
        messageType: 'file',
        attachment: {
          attachmentId: upload.attachmentId,
          storageKey: upload.upload.storageKey,
          contentType: 'application/octet-stream',
          sizeBytes: 2048,
          sha256: `deadbeef${suffix.replace(/[^a-fA-F0-9]/g, '0').padEnd(56, '0').slice(0, 56)}`,
          encryption: {
            encryptedKey: `wrapped-${suffix}`,
            nonce: `attachment-nonce-${suffix}`,
            algorithmHint: 'dev-wrap',
          },
        },
      },
    },
  });

  // Wait a tick for the WS fan-out to arrive, then assert the send was
  // delivered through the realtime channel.
  const wsArrival = await new Promise((resolve) => {
    const found = () => wsMessages.find((m) => m.id === sent.message.id);
    const cached = found();
    if (cached) return resolve(cached);
    const handler = () => {
      const match = found();
      if (match) {
        bobSocket.off('message.new', handler);
        resolve(match);
      }
    };
    bobSocket.on('message.new', handler);
    setTimeout(() => resolve(found() ?? null), 3000);
  });
  bobSocket.disconnect();
  if (!wsArrival) {
    throw new Error('Bob did not receive message.new over WebSocket');
  }
  if (wsArrival.id !== sent.message.id) {
    throw new Error(`Bob WS event id ${wsArrival.id} != sent id ${sent.message.id}`);
  }

  const listed = await requestJson(
    `/conversations/${conversation.conversation.id}/messages?limit=10`,
    { token: tokenA },
  );
  const download = await requestJson(`/attachments/${upload.attachmentId}/download-ticket`, {
    token: tokenA,
  });

  const transferInit = await requestJson('/device-transfer/init', {
    method: 'POST',
    token: tokenA,
    body: { oldDeviceId: regA.deviceId },
  });

  const claim = await requestJson('/device-transfer/claim', {
    method: 'POST',
    body: {
      sessionId: transferInit.sessionId,
      transferToken: transferInit.transferToken,
      newDeviceName: 'Alpha Transfer Device',
      platform: 'android',
      publicIdentityKey: `pub-transfer-${suffix}`,
      signedPrekeyBundle: `prekey-transfer-${suffix}`,
      authPublicKey: transferDevice.authPublicKey,
      authProof: signChallenge(
        `transfer-claim:${transferInit.sessionId}:${transferInit.transferToken}`,
        transferDevice.authPrivateKey,
      ),
    },
  });

  await requestJson('/device-transfer/approve', {
    method: 'POST',
    token: tokenA,
    body: {
      sessionId: transferInit.sessionId,
      claimId: claim.claimId,
    },
  });

  const transferComplete = await requestJson('/device-transfer/complete', {
    method: 'POST',
    body: {
      sessionId: transferInit.sessionId,
      transferToken: transferInit.transferToken,
      claimId: claim.claimId,
      authProof: signChallenge(
        `transfer-complete:${transferInit.sessionId}:${claim.claimId}:${transferInit.transferToken}`,
        transferDevice.authPrivateKey,
      ),
    },
  });

  console.log(
    JSON.stringify(
      {
        health: 'ok',
        handleA,
        handleB,
        conversationId: conversation.conversation.id,
        attachmentStatus: complete.uploadStatus,
        messageId: sent.message.id,
        listedItems: listed.items.length,
        downloadTicket: typeof download.ticket.downloadUrl === 'string',
        transferCompleted: transferComplete.newDeviceId != null,
        revokedDeviceId: transferComplete.revokedDeviceId,
        wsMessageDelivered: true,
      },
      null,
      2,
    ),
  );
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
