// CPaaS API key service — hashed keys stored in the new Prisma `ApiKey` model.
// Raw keys are high-entropy random values shown once at issue time; only the
// SHA-256 digest (hex) is stored. Verification is a unique-key lookup, so a
// leaked table never reveals usable keys.

import { createHash } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { AppError } from "../../lib/http.js";
import { randomToken } from "../../lib/crypto.js";
import { prisma } from "../../lib/prisma.js";
import { redis } from "../../lib/redis.js";
import { env } from "../../config/env.js";

export interface CpaasApiKeyView {
  id: string;
  name: string;
  prefix: string;
  revoked: boolean;
  createdAt: string;
}

export interface IssuedApiKey extends CpaasApiKeyView {
  /** Shown once; cannot be recovered afterwards. */
  raw: string;
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export class CpaasKeyService {
  async issue(name: string): Promise<IssuedApiKey> {
    const raw = `dsaialap_${randomToken(32)}`;
    const row = await prisma.apiKey.create({
      data: {
        name,
        keyHash: sha256Hex(raw),
        keyPrefix: raw.slice(0, 10),
      },
    });
    return {
      id: row.id,
      name: row.name,
      prefix: row.keyPrefix,
      revoked: false,
      createdAt: row.createdAt.toISOString(),
      raw,
    };
  }

  async authenticate(headerValue: string | undefined): Promise<CpaasApiKeyView> {
    if (!headerValue) {
      throw new AppError(401, "Missing x-dsaialap-key", "CPAAS_KEY_MISSING");
    }
    const row = await prisma.apiKey.findUnique({ where: { keyHash: sha256Hex(headerValue) } });
    if (!row) {
      throw new AppError(401, "Invalid CPaaS API key", "CPAAS_KEY_INVALID");
    }
    if (row.revokedAt) {
      throw new AppError(403, "CPaaS API key revoked", "CPAAS_KEY_REVOKED");
    }
    // Best-effort last-used marker; never fails the request.
    await prisma.apiKey
      .update({ where: { id: row.id }, data: { lastUsedAt: new Date() } })
      .catch(() => undefined);
    return {
      id: row.id,
      name: row.name,
      prefix: row.keyPrefix,
      revoked: false,
      createdAt: row.createdAt.toISOString(),
    };
  }

  async revoke(id: string): Promise<void> {
    await prisma.apiKey.update({ where: { id }, data: { revokedAt: new Date() } });
  }
}

export const cpaasKeyService = new CpaasKeyService();

export interface CpaasKeyRequest {
  cpaasKey: CpaasApiKeyView;
}

export function cpaasTenant(req: Request): CpaasApiKeyView {
  return (req as Request & CpaasKeyRequest).cpaasKey;
}

/** Middleware: authenticate x-dsaialap-key against the ApiKey table + per-key RPM cap. */
export function requireCpaasKey(req: Request, res: Response, next: NextFunction): void {
  void (async () => {
    try {
      const key = await cpaasKeyService.authenticate(req.header("x-dsaialap-key"));
      const windowSec = 60;
      const rpmKey = `${env.CPAAS_REDIS_PREFIX}apirpm:${key.id}`;
      const count = await redis.incr(rpmKey);
      if (count === 1) await redis.expire(rpmKey, windowSec);
      if (count > env.CPAAS_API_KEY_MAX_RPM) {
        throw new AppError(
          429,
          `CPaaS API rate limit exceeded (${env.CPAAS_API_KEY_MAX_RPM}/min)`,
          "CPAAS_KEY_RATE_LIMITED",
        );
      }
      res.setHeader("X-RateLimit-Limit", String(env.CPAAS_API_KEY_MAX_RPM));
      res.setHeader("X-RateLimit-Remaining", String(Math.max(env.CPAAS_API_KEY_MAX_RPM - count, 0)));
      (req as Request & CpaasKeyRequest).cpaasKey = key;
      next();
    } catch (err) {
      const status = err instanceof AppError ? err.status : 401;
      const code = err instanceof AppError ? err.code : "CPAAS_UNAUTHORIZED";
      const message = err instanceof Error ? err.message : "Unauthorized";
      if (!res.headersSent) {
        res.status(status).json({ ok: false, error: { code, message } });
      }
    }
  })();
}
