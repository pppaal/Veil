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
