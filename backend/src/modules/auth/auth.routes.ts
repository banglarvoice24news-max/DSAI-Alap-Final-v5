import { Router } from "express";
import { z } from "zod";
import { Language } from "@prisma/client";
import { env } from "../../config/env.js";
import { ok } from "../../lib/http.js";
import { authed, requireAuth } from "../../middleware/auth.js";
import { authService } from "./auth.service.js";

export const authRouter = Router();

const phoneSchema = z
  .string()
  .min(8)
  .max(20)
  .regex(/^\+[1-9]\d{7,14}$/, "E.164 phone number required");

authRouter.post("/otp/request", async (req, res, next) => {
  try {
    const body = z.object({ phoneNumber: phoneSchema }).parse(req.body);
    const result = await authService.requestOtp(body.phoneNumber);
    ok(res, result);
  } catch (err) {
    next(err);
  }
});

authRouter.post("/otp/verify", async (req, res, next) => {
  try {
    const body = z
      .object({
        phoneNumber: phoneSchema,
        otp: z.string().min(4).max(8),
        deviceId: z.string().min(8).max(128),
        publicKey: z.string().min(16),
        identityKey: z.string().optional(),
        signedPreKey: z.string().optional(),
        signedPreKeySig: z.string().optional(),
        displayName: z.string().max(80).optional(),
        language: z.nativeEnum(Language).optional(),
      })
      .parse(req.body);
    const result = await authService.verifyOtp({
      ...body,
      ip: req.ip || req.socket.remoteAddress || "0.0.0.0",
      userAgent: req.get("user-agent"),
      res,
    });
    ok(res, {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
      user: {
        id: result.user.id,
        phoneNumber: result.user.phoneNumber,
        publicKey: result.user.publicKey,
        displayName: result.user.displayName,
        language: result.user.language,
      },
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post("/refresh", async (req, res, next) => {
  try {
    const fromCookie = req.cookies?.[env.REFRESH_COOKIE_NAME] as string | undefined;
    const fromBody = z.object({ refreshToken: z.string().min(16).optional() }).safeParse(req.body);
    const raw = fromCookie || fromBody.data?.refreshToken;
    const tokens = await authService.refresh(
      raw,
      req.ip || req.socket.remoteAddress || "0.0.0.0",
      req.get("user-agent"),
      res,
    );
    ok(res, tokens);
  } catch (err) {
    next(err);
  }
});

authRouter.post("/logout", async (req, res, next) => {
  try {
    const raw = req.cookies?.[env.REFRESH_COOKIE_NAME] as string | undefined;
    await authService.logout(raw, res);
    ok(res, { loggedOut: true });
  } catch (err) {
    next(err);
  }
});

authRouter.post("/backup/register", requireAuth, async (req, res, next) => {
  try {
    const body = z.object({ backupKey: z.string().min(32) }).parse(req.body);
    await authService.setBackupKey(authed(req).sub, body.backupKey);
    ok(res, { registered: true });
  } catch (err) {
    next(err);
  }
});

authRouter.post("/backup/restore/start", async (req, res, next) => {
  try {
    const body = z.object({ phoneNumber: phoneSchema }).parse(req.body);
    const challenge = await authService.startBackupRestore(body.phoneNumber);
    ok(res, challenge);
  } catch (err) {
    next(err);
  }
});

authRouter.post("/backup/restore/complete", async (req, res, next) => {
  try {
    const body = z
      .object({
        challengeId: z.string().min(16),
        backupKey: z.string().min(32),
        deviceId: z.string().min(8).max(128),
      })
      .parse(req.body);
    const tokens = await authService.completeBackupRestore({
      ...body,
      ip: req.ip || req.socket.remoteAddress || "0.0.0.0",
      userAgent: req.get("user-agent"),
      res,
    });
    ok(res, tokens);
  } catch (err) {
    next(err);
  }
});
