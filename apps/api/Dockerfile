FROM node:22-alpine

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH

RUN corepack enable

WORKDIR /workspace

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/package.json
COPY packages/contracts/package.json packages/contracts/package.json
COPY apps/api/package.json apps/api/package.json

RUN pnpm install --frozen-lockfile

COPY packages packages
COPY apps/api apps/api

RUN ./node_modules/.bin/tsc -p packages/shared/tsconfig.json \
  && ./node_modules/.bin/tsc -p packages/contracts/tsconfig.json \
  && ./apps/api/node_modules/.bin/prisma generate --schema apps/api/prisma/schema.prisma \
  && ./node_modules/.bin/tsc -p apps/api/tsconfig.build.json

WORKDIR /workspace/apps/api

RUN chmod +x docker-entrypoint.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/v1/health || exit 1

CMD ["./docker-entrypoint.sh"]
