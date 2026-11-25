import { ValidationPipe } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { AppConfigService } from '../../src/common/config/app-config.service';
import { EphemeralStoreService } from '../../src/common/ephemeral-store.service';
import { PrismaService } from '../../src/common/prisma.service';
import {
  MAX_CIPHERTEXT_LENGTH,
  MAX_SECRET_BYTES_PER_CLIENT_DAY,
} from '../../src/modules/secret/dto/create-secret.dto';
import { SecretController } from '../../src/modules/secret/secret.controller';
import { SecretService } from '../../src/modules/secret/secret.service';
import { FakeEphemeralStoreService } from '../support/fake-services';

// POST /v1/s spends the daily quota of the caller's network, read from the
// configured client-address source: every address of an IPv6 /64 spends the
// same quota, so rotating addresses inside it gains nothing, and a network
// over its quota gets its own 429 while other networks still create.
describe('POST /s per-network quota', () => {
  let app: NestExpressApplication;
  let stored: number;

  beforeEach(async () => {
    stored = 0;
    const prisma = {
      $queryRaw: jest.fn(async () => [{ blobs: BigInt(stored), bytes: BigInt(0) }]),
      secretBlob: {
        create: jest.fn(async ({ data }: { data: { expiresAt: Date } }) => {
          stored += 1;
          return { id: `00000000-0000-4000-8000-${String(stored).padStart(12, '0')}`, ...data };
        }),
      },
    };
    const moduleRef = await Test.createTestingModule({
      controllers: [SecretController],
      providers: [
        SecretService,
        { provide: PrismaService, useValue: prisma },
        { provide: EphemeralStoreService, useValue: new FakeEphemeralStoreService() },
        { provide: AppConfigService, useValue: { clientIpSource: 'cf-connecting-ip' } },
      ],
    }).compile();
    app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false });
    app.useBodyParser('json', { limit: '512kb' });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  const create = (address: string) =>
    request(app.getHttpServer())
      .post('/s')
      .set('cf-connecting-ip', address)
      .send({ ciphertext: 'A'.repeat(MAX_CIPHERTEXT_LENGTH) });

  it('counts every address of one IPv6 /64 against one quota, and only that /64', async () => {
    const perDay = Math.floor(MAX_SECRET_BYTES_PER_CLIENT_DAY / MAX_CIPHERTEXT_LENGTH);
    for (let n = 1; n <= perDay; n += 1) {
      await create(`2001:db8:aa:bb::${n.toString(16)}`).expect(201);
    }

    const refused = await create('2001:db8:aa:bb:ffff:ffff:ffff:ffff').expect(429);
    expect(refused.body).toMatchObject({ code: 'secret_quota_exceeded' });
    await create('2001:db8:aa:bc::1').expect(201);
    await create('198.51.100.7').expect(201);
    expect(stored).toBe(perDay + 2);
  });
});
