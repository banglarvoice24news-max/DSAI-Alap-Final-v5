import type { NextFunction, Request, Response } from "express";
import { tokenService, type AccessClaims } from "../modules/auth/token.service.js";
import { fail } from "../lib/http.js";

export interface AuthedRequest extends Request {
  user: AccessClaims;
}

export function authed(req: Request): AccessClaims {
  return (req as unknown as AuthedRequest).user;
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  const token = header?.startsWith("Bearer ") ? header.slice(7) : undefined;
  if (!token) {
    fail(res, 401, "UNAUTHORIZED", "Missing access token");
    return;
  }
  void (async () => {
    try {
      const claims = tokenService.verifyAccess(token);
      await tokenService.assertSession(claims.sid, claims.sub);
      (req as AuthedRequest).user = claims;
      next();
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unauthorized";
      fail(res, 401, "UNAUTHORIZED", message);
    }
  })();
}
