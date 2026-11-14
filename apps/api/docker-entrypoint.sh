#!/bin/sh
set -eu

# The environment check and the production boot gate run first: some
# migrations delete data for good, so a deploy the API would refuse to boot
# must stop before `prisma migrate deploy` touches the database.
node dist/preflight.js
./node_modules/.bin/prisma migrate deploy --schema prisma/schema.prisma

exec pnpm start
