import { FakeEphemeralStoreService } from '../../../test/support/fake-services';
import {
  MAX_CIPHERTEXT_LENGTH,
  MAX_SECRET_BYTES_PER_CLIENT_DAY,
  MAX_SECRETS_PER_CLIENT_DAY,
  MAX_STORED_SECRET_BYTES,
  MAX_STORED_SECRETS,
  MAX_TTL_SECONDS,
  MIN_TTL_SECONDS,
} from './dto/create-secret.dto';
import { SecretService } from './secret.service';

// The project's FakePrismaService doesn't model SecretBlob, so we hand-roll
// just the prisma.secretBlob methods each test needs. $queryRaw answers the
// budget query with what the stored links already hold.
function makePrisma(overrides: {
  create?: jest.Mock;
  delete?: jest.Mock;
  stored?: { blobs: number; bytes: number };
}) {
  const stored = overrides.stored ?? { blobs: 0, bytes: 0 };
  return {
    $queryRaw: jest.fn(async () => [{ blobs: BigInt(stored.blobs), bytes: BigInt(stored.bytes) }]),
    secretBlob: {
      create: overrides.create ?? jest.fn(),
      delete: overrides.delete ?? jest.fn(),
    },
  } as never;
}

const service = (prisma: never, store = new FakeEphemeralStoreService()) =>
  new SecretService(prisma, store as never);

// The caller's network, as SecretController derives it with clientNetwork().
const CLIENT = '198.51.100.7';
const ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

describe('SecretService.create', () => {
  it('stores ciphertext and returns id + expiry', async () => {
    const create = jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));
    const svc = service(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('ENCRYPTED', 3600, CLIENT);

    expect(result.id).toBe(ID);
    // ~1h out, within a generous window.
    const delta = result.expiresAt.getTime() - before;
    expect(delta).toBeGreaterThan(3500 * 1000);
    expect(delta).toBeLessThan(3700 * 1000);
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ ciphertext: 'ENCRYPTED' }) }),
    );
  });

  it('clamps TTL below the floor up to the minimum', async () => {
    const create = jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));
    const svc = service(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('X', 1, CLIENT); // below MIN_TTL_SECONDS
    const delta = result.expiresAt.getTime() - before;
    expect(delta).toBeGreaterThanOrEqual((MIN_TTL_SECONDS - 1) * 1000);
  });

  it('clamps TTL above the ceiling down to the maximum', async () => {
    const create = jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));
    const svc = service(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('X', MAX_TTL_SECONDS * 10, CLIENT);
    const delta = result.expiresAt.getTime() - before;
    expect(delta).toBeLessThanOrEqual((MAX_TTL_SECONDS + 1) * 1000);
  });
});

// Creating a link needs no account, so what all links together may hold is
// capped relay-wide; the per-IP limit alone does not bound the database.
describe('SecretService.create budget', () => {
  const created = () =>
    jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));

  it.each([
    ['the links already fill the byte budget', { blobs: 1, bytes: MAX_STORED_SECRET_BYTES - 3 }],
    ['the links already fill the row budget', { blobs: MAX_STORED_SECRETS, bytes: 0 }],
  ])('refuses a new link when %s', async (_case, stored) => {
    const create = created();
    const svc = service(makePrisma({ create, stored }));

    await expect(svc.create('ABCD', undefined, CLIENT)).rejects.toMatchObject({
      status: 503,
      response: { code: 'secret_storage_full' },
    });
    expect(create).not.toHaveBeenCalled();
  });

  it('accepts a link that fits exactly', async () => {
    const create = created();
    const svc = service(
      makePrisma({ create, stored: { blobs: 1, bytes: MAX_STORED_SECRET_BYTES - 4 } }),
    );

    await expect(svc.create('ABCD', undefined, CLIENT)).resolves.toMatchObject({ id: ID });
  });
});

// Each client network has its own daily quota, spent before the relay-wide
// budget: one client that fills its quota is refused on its own (429) while
// every other client can still create, instead of the budget filling up and
// the feature failing for everyone (503).
describe('SecretService.create per-network quota', () => {
  const DAY_MS = 24 * 60 * 60 * 1000;
  const OTHER = '2001:db8:7:8::/64';
  const maximal = 'A'.repeat(MAX_CIPHERTEXT_LENGTH);
  const quotaRefusal = { status: 429, response: { code: 'secret_quota_exceeded' } };

  // Stored links as the budget scan sees them: what this test's creates added.
  function storingPrisma() {
    const stored = { blobs: 0, bytes: 0 };
    let next = 0;
    const create = jest.fn(async ({ data }: { data: { ciphertext: string; expiresAt: Date } }) => {
      stored.blobs += 1;
      stored.bytes += Buffer.byteLength(data.ciphertext, 'utf8');
      next += 1;
      return { id: `id-${next}`, expiresAt: data.expiresAt };
    });
    const prisma = {
      $queryRaw: jest.fn(async () => [
        { blobs: BigInt(stored.blobs), bytes: BigInt(stored.bytes) },
      ]),
      secretBlob: { create, delete: jest.fn() },
    };
    return { prisma, create, stored };
  }

  // Creates `ciphertext` links from `client` until one is refused; returns how
  // many were accepted and the refusal.
  async function createUntilRefused(svc: SecretService, client: string, ciphertext: string) {
    for (let accepted = 0; accepted <= MAX_SECRETS_PER_CLIENT_DAY + 1; accepted += 1) {
      try {
        await svc.create(ciphertext, MAX_TTL_SECONDS, client);
      } catch (refusal) {
        return { accepted, refusal };
      }
    }
    throw new Error('the quota never refused');
  }

  let now: number;
  beforeEach(() => {
    now = Date.UTC(2026, 10, 14, 0, 0, 1);
    jest.spyOn(Date, 'now').mockImplementation(() => now);
  });
  afterEach(() => jest.restoreAllMocks());

  it('refuses one network at its byte quota while another network can still create', async () => {
    const { prisma, create } = storingPrisma();
    const svc = service(prisma as never);

    const { accepted, refusal } = await createUntilRefused(svc, CLIENT, maximal);

    expect(accepted).toBe(Math.floor(MAX_SECRET_BYTES_PER_CLIENT_DAY / MAX_CIPHERTEXT_LENGTH));
    expect(refusal).toMatchObject(quotaRefusal);
    // Refused on the quota, before the relay-wide scan.
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(accepted);
    await expect(svc.create(maximal, MAX_TTL_SECONDS, OTHER)).resolves.toMatchObject({
      id: expect.any(String),
    });
    expect(create).toHaveBeenCalledTimes(accepted + 1);
  });

  it('refuses one network at its link quota while another network can still create', async () => {
    const { prisma } = storingPrisma();
    const svc = service(prisma as never);

    const { accepted, refusal } = await createUntilRefused(svc, CLIENT, 'tiny');

    expect(accepted).toBe(MAX_SECRETS_PER_CLIENT_DAY);
    expect(refusal).toMatchObject(quotaRefusal);
    await expect(svc.create('tiny', undefined, OTHER)).resolves.toBeDefined();
  });

  it('does not count a refused link: a smaller one that still fits is accepted', async () => {
    const { prisma } = storingPrisma();
    const svc = service(prisma as never);
    const size = 100_000;

    const { accepted, refusal } = await createUntilRefused(svc, CLIENT, 'B'.repeat(size));
    expect(refusal).toMatchObject(quotaRefusal);
    const left = MAX_SECRET_BYTES_PER_CLIENT_DAY - accepted * size;
    expect(left).toBeGreaterThan(0);
    expect(left).toBeLessThan(size);

    await expect(svc.create('C'.repeat(left), undefined, CLIENT)).resolves.toBeDefined();
    await expect(svc.create('D', undefined, CLIENT)).rejects.toMatchObject(quotaRefusal);
  });

  it('gives the quota back when the relay-wide budget refuses or the insert fails', async () => {
    const stored = { blobs: MAX_STORED_SECRETS, bytes: 0 };
    const insert = jest.fn(async (): Promise<unknown> => {
      throw new Error('insert failed');
    });
    const prisma = {
      $queryRaw: jest.fn(async () => [
        { blobs: BigInt(stored.blobs), bytes: BigInt(stored.bytes) },
      ]),
      secretBlob: { create: insert, delete: jest.fn() },
    };
    const svc = service(prisma as never);

    for (let attempt = 0; attempt <= MAX_SECRETS_PER_CLIENT_DAY; attempt += 1) {
      now += 10_000; // past the reuse window, so every attempt scans
      await expect(svc.create('tiny', undefined, CLIENT)).rejects.toMatchObject({
        status: 503,
        response: { code: 'secret_storage_full' },
      });
    }
    stored.blobs = 0;
    now += 10_000;
    for (let attempt = 0; attempt <= MAX_SECRETS_PER_CLIENT_DAY; attempt += 1) {
      await expect(svc.create('tiny', undefined, CLIENT)).rejects.toThrow('insert failed');
    }
    insert.mockImplementation(async () => ({ id: ID, expiresAt: new Date(now) }));

    await expect(svc.create('tiny', undefined, CLIENT)).resolves.toMatchObject({ id: ID });
  });

  it('renews the quota on the next UTC day', async () => {
    const { prisma } = storingPrisma();
    const svc = service(prisma as never);
    await createUntilRefused(svc, CLIENT, 'tiny');

    now = Date.UTC(2026, 10, 14, 23, 59, 59);
    await expect(svc.create('tiny', undefined, CLIENT)).rejects.toMatchObject(quotaRefusal);
    now = Date.UTC(2026, 10, 15, 0, 0, 0);
    await expect(svc.create('tiny', undefined, CLIENT)).resolves.toBeDefined();
  });

  it('keys the quota by a digest of the day and network that expires at the next UTC midnight', async () => {
    const store = new FakeEphemeralStoreService();
    const spend = jest.spyOn(store, 'incrementFieldsUntil');
    const { prisma } = storingPrisma();
    const svc = service(prisma as never, store);

    await svc.create('tiny', undefined, CLIENT);

    const [key, amounts, expiresAtMs] = spend.mock.calls[0];
    expect(key).toMatch(/^secret:quota:[A-Za-z0-9_-]{43}$/);
    expect(key).not.toContain(CLIENT);
    expect(amounts).toEqual({ links: 1, bytes: 4 });
    expect(expiresAtMs).toBe(Date.UTC(2026, 10, 15));
  });

  it("caps one network's maximal links over a link's whole lifetime at an eighth of the budget", async () => {
    const { prisma, stored } = storingPrisma();
    const svc = service(prisma as never);
    // A link lives at most seven days, so links from eight UTC days can be
    // alive at once. Nothing is opened or swept here: every link still counts.
    const daysAlive = Math.ceil((MAX_TTL_SECONDS * 1000) / DAY_MS) + 1;

    for (let day = 0; day < daysAlive; day += 1) {
      now = Date.UTC(2026, 10, 14 + day, 0, 0, 1);
      const { refusal } = await createUntilRefused(svc, CLIENT, maximal);
      expect(refusal).toMatchObject(quotaRefusal);
    }

    expect(stored.bytes).toBe(daysAlive * MAX_SECRET_BYTES_PER_CLIENT_DAY);
    expect(stored.bytes).toBeLessThanOrEqual(MAX_STORED_SECRET_BYTES / 8);
    expect(stored.blobs).toBeLessThan(MAX_STORED_SECRETS);
    await expect(svc.create(maximal, MAX_TTL_SECONDS, OTHER)).resolves.toBeDefined();
  });
});

// Once the relay-wide budget is full, every create would scan secret_blobs
// just to be refused. A recent scan may refuse without scanning again, but it
// is never trusted to accept.
describe('SecretService.create budget scan reuse', () => {
  let now: number;
  beforeEach(() => {
    now = Date.UTC(2026, 10, 14, 12);
    jest.spyOn(Date, 'now').mockImplementation(() => now);
  });
  afterEach(() => jest.restoreAllMocks());

  it('refuses from a scan that found the budget full for five seconds, then scans again', async () => {
    const stored = { blobs: 1, bytes: MAX_STORED_SECRET_BYTES - 10 };
    const prisma = makePrisma({ stored }) as unknown as { $queryRaw: jest.Mock };
    const svc = service(prisma as never);
    const full = { status: 503, response: { code: 'secret_storage_full' } };

    await expect(svc.create('A'.repeat(11), undefined, CLIENT)).rejects.toMatchObject(full);
    await expect(svc.create('A'.repeat(11), undefined, '203.0.113.1')).rejects.toMatchObject(full);
    now += 4_999;
    await expect(svc.create('A'.repeat(11), undefined, '203.0.113.2')).rejects.toMatchObject(full);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);

    now += 1;
    await expect(svc.create('A'.repeat(11), undefined, '203.0.113.3')).rejects.toMatchObject(full);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
  });

  it('scans again for a link the last scan did not refuse', async () => {
    const create = jest.fn(async () => ({ id: ID, expiresAt: new Date(now) }));
    const stored = { blobs: 1, bytes: MAX_STORED_SECRET_BYTES - 10 };
    const prisma = makePrisma({ create, stored }) as unknown as { $queryRaw: jest.Mock };
    const svc = service(prisma as never);

    await expect(svc.create('A'.repeat(11), undefined, CLIENT)).rejects.toMatchObject({
      status: 503,
    });
    await expect(svc.create('A'.repeat(10), undefined, CLIENT)).resolves.toMatchObject({ id: ID });
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
  });
});

describe('SecretService.burn', () => {
  it('returns ciphertext and deletes the row on first read', async () => {
    const future = new Date(Date.now() + 60_000);
    const del = jest.fn(async () => ({ ciphertext: 'ENCRYPTED', expiresAt: future }));
    const svc = service(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBe('ENCRYPTED');
    expect(del).toHaveBeenCalledWith(expect.objectContaining({ where: { id: ID } }));
  });

  it('returns null when the link was already opened (record gone)', async () => {
    const del = jest.fn(async () => {
      throw new Error('P2025: record not found');
    });
    const svc = service(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBeNull();
  });

  it('returns null when the row had already expired', async () => {
    const past = new Date(Date.now() - 1000);
    const del = jest.fn(async () => ({ ciphertext: 'ENCRYPTED', expiresAt: past }));
    const svc = service(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBeNull();
  });
});
