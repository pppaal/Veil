-- 0011 and 0016 created secret_blobs.id and one_time_prekeys.id with
-- DEFAULT gen_random_uuid(), while schema.prisma declares @default(uuid()),
-- which Prisma fills in on the client and never maps to a database default.
-- 0008 dropped the same default from every other table; this does it for
-- these two, so the migrations and the schema describe the same database
-- (test/unit/migrations-schema-parity.spec.ts). Every insert goes through
-- Prisma, which always sends the id, so nothing relied on the default.
ALTER TABLE "one_time_prekeys" ALTER COLUMN "id" DROP DEFAULT;
ALTER TABLE "secret_blobs" ALTER COLUMN "id" DROP DEFAULT;
