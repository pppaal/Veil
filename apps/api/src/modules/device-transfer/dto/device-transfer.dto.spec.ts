import 'reflect-metadata';
import { randomBytes, randomUUID } from 'node:crypto';

import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

import { RegisterDto } from '../../auth/dto/register.dto';
import { DeviceTransferClaimDto } from './device-transfer.dto';

const key = () => randomBytes(32).toString('base64url');
const claim = (overrides: Record<string, unknown> = {}) => ({
  sessionId: randomUUID(),
  transferToken: 'token',
  newDeviceName: 'Pixel',
  platform: 'android',
  publicIdentityKey: key(),
  signedPrekeyBundle: key(),
  authPublicKey: key(),
  authProof: 'proof',
  ...overrides,
});
const invalidFields = async (body: Record<string, unknown>) =>
  (await validate(plainToInstance(DeviceTransferClaimDto, body))).map((error) => error.property);

// A transferred device's keys are served by the directory exactly like a
// registered one's, so the claim must hold them to the same formats; the two
// the claimant fingerprint covers must also have only one reading.
describe('DeviceTransferClaimDto keys', () => {
  it('accepts keys in the formats registration accepts', async () => {
    const body = claim({ publicIdentityKey: `${randomBytes(32).toString('base64url')}=` });
    expect(await invalidFields(body)).toEqual([]);
    expect(
      await validate(
        plainToInstance(RegisterDto, {
          handle: 'pixel',
          deviceName: 'Pixel',
          platform: 'android',
          publicIdentityKey: body.publicIdentityKey,
          signedPrekeyBundle: body.signedPrekeyBundle,
          authPublicKey: body.authPublicKey,
        }),
      ),
    ).toEqual([]);
  });

  it.each([
    ['free text', 'attacker ik'],
    ['standard base64 characters', 'ab+/cd'],
  ])('refuses %s in any key', async (_case, value) => {
    for (const field of ['publicIdentityKey', 'signedPrekeyBundle', 'authPublicKey']) {
      expect(await invalidFields(claim({ [field]: value }))).toEqual([field]);
    }
  });

  it.each([
    ['leftover bits set', 'AB'],
    ['a length no byte string has', 'AAAAA'],
    ['padding on a full quantum', 'AAAA=='],
    ['padding of the wrong length', 'AAA=='],
  ])('refuses a fingerprinted key with %s', async (_case, value) => {
    expect(await invalidFields(claim({ publicIdentityKey: value }))).toEqual(['publicIdentityKey']);
    expect(await invalidFields(claim({ authPublicKey: value }))).toEqual(['authPublicKey']);
  });

  it('refuses a padded auth key, as registration does', async () => {
    expect(await invalidFields(claim({ authPublicKey: 'AAA=' }))).toEqual(['authPublicKey']);
  });
});
