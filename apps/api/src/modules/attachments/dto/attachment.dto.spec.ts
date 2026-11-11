import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

import { CreateUploadTicketDto } from './attachment.dto';

const base = { contentType: 'image/png', sizeBytes: 1024 };
const make = (sha256: string) => plainToInstance(CreateUploadTicketDto, { ...base, sha256 });
const sha256Errors = async (sha256: string) =>
  (await validate(make(sha256))).filter((e) => e.property === 'sha256');

describe('CreateUploadTicketDto.sha256', () => {
  it('accepts a canonical 64-hex digest (either case)', async () => {
    expect(await sha256Errors('a'.repeat(64))).toHaveLength(0);
    expect(await sha256Errors('A1B2C3D4'.repeat(8))).toHaveLength(0);
  });

  it('rejects a digest that is not exactly 64 chars', async () => {
    expect((await sha256Errors('abcd1234')).length).toBeGreaterThan(0); // too short
    expect((await sha256Errors('a'.repeat(65))).length).toBeGreaterThan(0); // too long
  });

  it('rejects non-hex characters and hyphens the old regex allowed', async () => {
    expect((await sha256Errors('z'.repeat(64))).length).toBeGreaterThan(0);
    expect((await sha256Errors('a'.repeat(32) + '-' + 'a'.repeat(31))).length).toBeGreaterThan(0);
  });
});

describe('CreateUploadTicketDto.attachmentId', () => {
  const valid = { ...base, sha256: 'a'.repeat(64) };
  // The global ValidationPipe runs with these options, so passing here also
  // proves the field is whitelisted rather than rejected as unknown.
  const errorsFor = async (body: Record<string, unknown>) =>
    validate(plainToInstance(CreateUploadTicketDto, body), {
      whitelist: true,
      forbidNonWhitelisted: true,
    });

  it('may be absent, so clients that let the relay assign the id keep working', async () => {
    expect(await errorsFor(valid)).toHaveLength(0);
  });

  it('accepts a UUID v4', async () => {
    expect(
      await errorsFor({ ...valid, attachmentId: '3b241101-e2bb-4255-8caf-4136c566a962' }),
    ).toHaveLength(0);
  });

  it.each([
    ['an empty string', ''],
    ['a non-UUID', 'attachment-1'],
    ['an unhyphenated UUID', '3b241101e2bb42558caf4136c566a962'],
    // Version 1 embeds a timestamp and a node id.
    ['a UUID v1', 'a8098c1a-f86e-11da-bd1a-00112444be1e'],
    ['a number', 42],
  ])('rejects %s', async (_label, attachmentId) => {
    const errors = await errorsFor({ ...valid, attachmentId });
    expect(errors.map((e) => e.property)).toEqual(['attachmentId']);
  });
});
