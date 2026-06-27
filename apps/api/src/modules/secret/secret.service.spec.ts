import { MAX_TTL_SECONDS, MIN_TTL_SECONDS } from './dto/create-secret.dto';
import { SecretService } from './secret.service';

// The project's FakePrismaService doesn't model SecretBlob, so we hand-roll
// just the prisma.secretBlob methods each test needs.
function makePrisma(overrides: { create?: jest.Mock; delete?: jest.Mock }) {
  return {
    secretBlob: {
      create: overrides.create ?? jest.fn(),
      delete: overrides.delete ?? jest.fn(),
    },
  } as never;
}

const ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

describe('SecretService.create', () => {
  it('stores ciphertext and returns id + expiry', async () => {
    const create = jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));
    const svc = new SecretService(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('ENCRYPTED', 3600);

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
    const svc = new SecretService(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('X', 1); // below MIN_TTL_SECONDS
    const delta = result.expiresAt.getTime() - before;
    expect(delta).toBeGreaterThanOrEqual((MIN_TTL_SECONDS - 1) * 1000);
  });

  it('clamps TTL above the ceiling down to the maximum', async () => {
    const create = jest.fn(async ({ data }: { data: { expiresAt: Date } }) => ({
      id: ID,
      expiresAt: data.expiresAt,
    }));
    const svc = new SecretService(makePrisma({ create }));

    const before = Date.now();
    const result = await svc.create('X', MAX_TTL_SECONDS * 10);
    const delta = result.expiresAt.getTime() - before;
    expect(delta).toBeLessThanOrEqual((MAX_TTL_SECONDS + 1) * 1000);
  });
});

describe('SecretService.burn', () => {
  it('returns ciphertext and deletes the row on first read', async () => {
    const future = new Date(Date.now() + 60_000);
    const del = jest.fn(async () => ({ ciphertext: 'ENCRYPTED', expiresAt: future }));
    const svc = new SecretService(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBe('ENCRYPTED');
    expect(del).toHaveBeenCalledWith(expect.objectContaining({ where: { id: ID } }));
  });

  it('returns null when the link was already opened (record gone)', async () => {
    const del = jest.fn(async () => {
      throw new Error('P2025: record not found');
    });
    const svc = new SecretService(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBeNull();
  });

  it('returns null when the row had already expired', async () => {
    const past = new Date(Date.now() - 1000);
    const del = jest.fn(async () => ({ ciphertext: 'ENCRYPTED', expiresAt: past }));
    const svc = new SecretService(makePrisma({ delete: del }));

    expect(await svc.burn(ID)).toBeNull();
  });
});
