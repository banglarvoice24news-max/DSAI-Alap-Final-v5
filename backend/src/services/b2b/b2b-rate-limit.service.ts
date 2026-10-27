import { redis } from "../../lib/redis.js";
import { AppError } from "../../lib/http.js";
import type { B2bTenant } from "./b2b-key.service.js";

export class B2bRateLimitService {
  async consume(tenant: B2bTenant): Promise<{ remaining: number; resetSeconds: number }> {
    const windowSec = 60;
    const key = `b2b:rpm:${tenant.id}`;
    const count = await redis.incr(key);
    if (count === 1) {
      await redis.expire(key, windowSec);
    }
    const ttl = await redis.ttl(key);
    if (count > tenant.rpm) {
      throw new AppError(
        429,
        `B2B rate limit exceeded for ${tenant.tier} tier (${tenant.rpm} rpm)`,
        "B2B_RATE_LIMITED",
      );
    }
    return { remaining: Math.max(tenant.rpm - count, 0), resetSeconds: Math.max(ttl, 1) };
  }
}

export const b2bRateLimitService = new B2bRateLimitService();
