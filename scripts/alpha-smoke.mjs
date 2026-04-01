import { createPrivateKey, generateKeyPairSync, sign } from 'node:crypto';

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
      sha256: `hash-${suffix}`,
    },
  });

  const uploadPut = await fetch(upload.upload.uploadUrl, {
    method: 'PUT',
    headers: upload.upload.headers,
    body: Buffer.from(Array.from({ length: 2048 }, (_, index) => index % 251)),
  });
  if (!uploadPut.ok) {
    throw new Error(`upload PUT ${uploadPut.status} ${await uploadPut.text()}`);
  }

  const complete = await requestJson('/attachments/complete', {
    method: 'POST',
    token: tokenA,
    body: {
      attachmentId: upload.attachmentId,
      uploadStatus: 'uploaded',
    },
  });

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
          sha256: `hash-${suffix}`,
          encryption: {
            encryptedKey: `wrapped-${suffix}`,
            nonce: `attachment-nonce-${suffix}`,
            algorithmHint: 'dev-wrap',
          },
        },
      },
    },
  });

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
