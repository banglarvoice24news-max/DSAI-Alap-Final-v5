import type { NextFunction, Request, Response } from "express";

export function cloudflareSecurityHeaders(req: Request, res: Response, next: NextFunction): void {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("X-DNS-Prefetch-Control", "off");
  res.setHeader("X-Permitted-Cross-Domain-Policies", "none");
  const cfRay = req.header("cf-ray");
  const cfConnectingIp = req.header("cf-connecting-ip");
  if (cfRay) res.setHeader("X-Dsaialap-Edge", "cloudflare");
  if (cfConnectingIp) {
    req.headers["x-forwarded-for"] = cfConnectingIp;
  }
  next();
}
