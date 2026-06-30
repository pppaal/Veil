import { RecoveryService } from './recovery.service';

// FakePrismaService doesn't model RecoveryBlob, so we hand-roll just the
// prisma.recoveryBlob methods each test needs.
function makePrisma(overrides: {
  upsert?: jest.Mock;
  findUnique?: jest.Mock;
  deleteMany?: jest.Mock;
}) {
  return {
    recoveryBlob: {
      upsert: overrides.upsert ?? jest.fn(),
      findUnique: overrides.findUnique ?? jest.fn(),
      deleteMany: overrides.deleteMany ?? jest.fn(),
    },
  } as never;
}

const USER = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

describe('RecoveryService.upsert', () => {
  it('stores the opaque ciphertext keyed by user and returns updatedAt', async () => {
    const now = new Date();
    const upsert = jest.fn(async () => ({ updatedAt: now }));
    const svc = new RecoveryService(makePrisma({ upsert }));

    const result = await svc.upsert(USER, 'veilbak:v1:salt:nonce:ct:mac');

    expect(result.updatedAt).toBe(now);
    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: USER },
        update: { ciphertext: 'veilbak:v1:salt:nonce:ct:mac', format: 'veilbak:v1' },
        create: expect.objectContaining({ userId: USER, format: 'veilbak:v1' }),
      }),
    );
  });

  it('replaces a prior backup (upsert update branch) and honours an explicit format', async () => {
    const upsert = jest.fn(async () => ({ updatedAt: new Date() }));
    const svc = new RecoveryService(makePrisma({ upsert }));

    await svc.upsert(USER, 'CT', 'veilbak:v2');

    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: { ciphertext: 'CT', format: 'veilbak:v2' },
        create: expect.objectContaining({ format: 'veilbak:v2' }),
      }),
    );
  });
});

describe('RecoveryService.get', () => {
  it('returns the stored backup for the caller', async () => {
    const updatedAt = new Date();
    const findUnique = jest.fn(async () => ({
      ciphertext: 'CT',
      format: 'veilbak:v1',
      updatedAt,
    }));
    const svc = new RecoveryService(makePrisma({ findUnique }));

    const blob = await svc.get(USER);

    expect(blob).toEqual({ ciphertext: 'CT', format: 'veilbak:v1', updatedAt });
    expect(findUnique).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: USER } }));
  });

  it('returns null when the caller has no backup', async () => {
    const findUnique = jest.fn(async () => null);
    const svc = new RecoveryService(makePrisma({ findUnique }));

    expect(await svc.get(USER)).toBeNull();
  });
});

describe('RecoveryService.remove', () => {
  it('reports deleted=true when a backup existed', async () => {
    const deleteMany = jest.fn(async () => ({ count: 1 }));
    const svc = new RecoveryService(makePrisma({ deleteMany }));

    expect(await svc.remove(USER)).toEqual({ deleted: true });
    expect(deleteMany).toHaveBeenCalledWith({ where: { userId: USER } });
  });

  it('is idempotent — deleted=false when there was nothing to remove', async () => {
    const deleteMany = jest.fn(async () => ({ count: 0 }));
    const svc = new RecoveryService(makePrisma({ deleteMany }));

    expect(await svc.remove(USER)).toEqual({ deleted: false });
  });
});
