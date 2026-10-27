# syntax=docker/dockerfile:1.7
#
# Backend-only multi-stage build (frontend is deployed on Vercel, not here).
#
# The final `runtime` image contains only the compiled app and production
# dependencies: no TypeScript, no compilers, no dev dependencies, no secrets.
# Database migrations run from the separate `migrate` target as a one-shot
# compose service - never from the app container's CMD.
#
# Base images are pinned by digest for reproducible builds. Requires BuildKit
# (DOCKER_BUILDKIT=1 / docker buildx) for the cache mount below.

ARG NODE_IMAGE=node:22-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32

# ---------- base: runtime libs + unprivileged user ----------
# Base image is pinned by digest through NODE_IMAGE, which hadolint cannot see.
# hadolint ignore=DL3006
FROM ${NODE_IMAGE} AS base
# openssl: required by the Prisma query engine at runtime (musl + OpenSSL 3).
# apk patch versions drift, so pinning them would fight the digest-pinned base.
# hadolint ignore=DL3018
RUN apk add --no-cache openssl \
  && addgroup -g 10001 -S nexus \
  && adduser -u 10001 -S nexus -G nexus
WORKDIR /app

# ---------- deps: full dependency tree (dev included) for build + migrate ----------
FROM base AS deps
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

# ---------- build: generate Prisma client + compile, then drop dev deps ----------
FROM deps AS build
# `prisma generate` only needs a syntactically valid URL. This placeholder is
# never read at runtime and is scoped to this stage, so it is not a secret and
# does not reach the runtime image.
ENV DATABASE_URL="postgresql://placeholder:placeholder@127.0.0.1:5432/placeholder?schema=public"
COPY tsconfig.json ./
COPY prisma ./prisma
COPY src ./src
RUN npx prisma generate \
  && npm run build \
  && npm prune --omit=dev

# ---------- runtime: final image (non-root, no build tools) ----------
FROM base AS runtime
ENV NODE_ENV=production \
    PORT=3001 \
    HOST=0.0.0.0
COPY --from=build --chown=nexus:nexus /app/node_modules ./node_modules
COPY --from=build --chown=nexus:nexus /app/dist ./dist
COPY --from=build --chown=nexus:nexus /app/package.json ./package.json
USER nexus
EXPOSE 3001
# Liveness via the app's own /health endpoint using Node's global fetch, so the
# image needs no curl/wget. (A failing healthcheck does not restart the
# container by itself; compose/orchestrator policy does.)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e 'fetch("http://127.0.0.1:"+(process.env.PORT||3001)+"/health").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))'
CMD ["node", "dist/index.js"]

# ---------- migrate: one-shot `prisma migrate deploy` (separate image) ----------
FROM base AS migrate
WORKDIR /app
COPY --from=deps --chown=nexus:nexus /app/node_modules ./node_modules
COPY --from=deps --chown=nexus:nexus /app/package.json ./package.json
COPY --chown=nexus:nexus prisma ./prisma
USER nexus
CMD ["npx", "prisma", "migrate", "deploy"]
