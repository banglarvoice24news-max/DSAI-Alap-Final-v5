import express from "express";
import type { Request, Response } from "express";
import cors from "cors";
import helmet from "helmet";
import cookieParser from "cookie-parser";
import rateLimit from "express-rate-limit";
import { env } from "./config/env.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { userRouter } from "./modules/users/user.routes.js";
import { messageRouter } from "./modules/messages/message.routes.js";
import { b2bRouter } from "./modules/b2b/b2b.routes.js";
import { errorHandler } from "./middleware/error-handler.js";
import { sanitizeBody } from "./middlewares/sanitize.js";
import { cloudflareSecurityHeaders } from "./middlewares/security-headers.js";

export async function createApp() {
  const app = express();
  app.set("trust proxy", 1);
  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginResourcePolicy: { policy: "cross-origin" },
      hsts: env.NODE_ENV === "production" ? { maxAge: 15552000, includeSubDomains: true } : false,
    }),
  );
  app.use(cloudflareSecurityHeaders);
  const origins = [...env.CORS_ORIGINS, ...env.MASKED_ORIGINS];
  app.use(
    cors({
      origin: (origin, cb) => {
        if (!origin || origins.includes(origin)) {
          cb(null, true);
          return;
        }
        cb(null, false);
      },
      credentials: true,
      allowedHeaders: ["Content-Type", "Authorization", "x-dsaialap-key", "CF-Connecting-IP"],
      exposedHeaders: ["X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"],
    }),
  );
  app.use(express.json({ limit: "256kb", verify: captureRawBody }));
  app.use(express.urlencoded({ extended: false }));
  app.use(cookieParser());
  app.use(sanitizeBody);
  app.use(
    rateLimit({
      windowMs: 60_000,
      limit: 120,
      standardHeaders: true,
      legacyHeaders: false,
      skip: (req) =>
        req.path.startsWith("/api/b2b") ||
        req.path.startsWith("/api/cpaas/webhook") ||
        req.path === "/health",
    }),
  );

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "nexus-api", ts: new Date().toISOString() });
  });

  app.use("/api/auth", authRouter);
  app.use("/api/users", userRouter);
  app.use("/api/messages", messageRouter);
  app.use("/api/b2b", b2bRouter);

  // §3.2: the CPaaS/telecom layer is mounted only when explicitly enabled.
  // Every telecom import happens lazily through this branch so the default
  // deployment (no ENABLE_CPAAS_LAYER) has zero startup cost from the layer.
  if (env.ENABLE_CPAAS_LAYER) {
    const { cpaasRouter } = await import("./modules/cpaas/cpaas.routes.js");
    app.use("/api/cpaas", cpaasRouter);
  }

  app.use(errorHandler);
  return app;
}

/** Keep the raw request bytes for provider webhook signature verification. */
function captureRawBody(req: Request, _res: Response, buf: Buffer): void {
  (req as Request & { rawBody?: string }).rawBody = buf.toString("utf8");
}
