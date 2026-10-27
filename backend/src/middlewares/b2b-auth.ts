import type { NextFunction, Request, Response } from "express";
import { b2bKeyService, type B2bTenant } from "../services/b2b/b2b-key.service.js";
import { b2bRateLimitService } from "../services/b2b/b2b-rate-limit.service.js";
import { fail } from "../lib/http.js";

export interface B2bRequest extends Request {
  b2b: B2bTenant;
}

export function b2bTenant(req: Request): B2bTenant {
  return (req as B2bRequest).b2b;
}

export function requireB2bKey(req: Request, res: Response, next: NextFunction): void {
  void (async () => {
    try {
      const tenant = b2bKeyService.verify(req.header("x-dsaialap-key"));
      const quota = await b2bRateLimitService.consume(tenant);
      res.setHeader("X-RateLimit-Limit", String(tenant.rpm));
      res.setHeader("X-RateLimit-Remaining", String(quota.remaining));
      res.setHeader("X-RateLimit-Reset", String(quota.resetSeconds));
      (req as B2bRequest).b2b = tenant;
      next();
    } catch (err) {
      const status = typeof err === "object" && err && "status" in err ? Number((err as { status: number }).status) : 401;
      const code = typeof err === "object" && err && "code" in err ? String((err as { code: string }).code) : "B2B_UNAUTHORIZED";
      const message = err instanceof Error ? err.message : "Unauthorized";
      fail(res, Number.isFinite(status) ? status : 401, code, message);
    }
  })();
}
