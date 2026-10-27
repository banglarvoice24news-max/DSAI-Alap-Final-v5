import { Router } from "express";
import { z } from "zod";
import { Language } from "@prisma/client";
import { ok } from "../../lib/http.js";
import { authed, requireAuth } from "../../middleware/auth.js";
import { userService } from "./user.service.js";
import { fcmService } from "../push/fcm.service.js";
import { e2eeService } from "../e2ee/e2ee.service.js";

export const userRouter = Router();
userRouter.use(requireAuth);

userRouter.get("/me", async (req, res, next) => {
  try {
    const user = await userService.me(authed(req).sub);
    ok(res, user);
  } catch (err) {
    next(err);
  }
});

userRouter.patch("/me", async (req, res, next) => {
  try {
    const body = z
      .object({
        displayName: z.string().max(80).optional(),
        about: z.string().max(140).optional(),
        avatarUrl: z.string().url().optional(),
        language: z.nativeEnum(Language).optional(),
      })
      .parse(req.body);
    const user = await userService.updateProfile(authed(req).sub, body);
    ok(res, user);
  } catch (err) {
    next(err);
  }
});

userRouter.get("/lookup/:phone", async (req, res, next) => {
  try {
    const phone = z
      .string()
      .regex(/^\+[1-9]\d{7,14}$/)
      .parse(req.params.phone);
    const user = await userService.lookupByPhone(phone);
    ok(res, user);
  } catch (err) {
    next(err);
  }
});

userRouter.post("/fcm-token", async (req, res, next) => {
  try {
    const body = z.object({ token: z.string().min(10) }).parse(req.body);
    await fcmService.registerToken(authed(req).sub, body.token);
    ok(res, { registered: true });
  } catch (err) {
    next(err);
  }
});

userRouter.post("/block/:userId", async (req, res, next) => {
  try {
    await userService.block(authed(req).sub, req.params.userId);
    ok(res, { blocked: true });
  } catch (err) {
    next(err);
  }
});

userRouter.post("/unblock/:userId", async (req, res, next) => {
  try {
    await userService.unblock(authed(req).sub, req.params.userId);
    ok(res, { unblocked: true });
  } catch (err) {
    next(err);
  }
});

userRouter.get("/blocked", async (req, res, next) => {
  try {
    const list = await userService.blockedList(authed(req).sub);
    ok(res, list);
  } catch (err) {
    next(err);
  }
});

userRouter.put("/e2ee/bundle", async (req, res, next) => {
  try {
    const body = z
      .object({
        identityKey: z.string().min(16),
        signedPreKey: z.string().min(16),
        signedPreKeySig: z.string().min(16),
        publicKey: z.string().min(16),
        oneTimePreKeys: z
          .array(z.object({ keyId: z.number().int(), publicKey: z.string().min(16) }))
          .max(100),
      })
      .parse(req.body);
    await e2eeService.publishBundle(authed(req).sub, body);
    ok(res, { published: true });
  } catch (err) {
    next(err);
  }
});

userRouter.get("/e2ee/bundle/:userId", async (req, res, next) => {
  try {
    const bundle = await e2eeService.fetchBundle(req.params.userId);
    ok(res, bundle);
  } catch (err) {
    next(err);
  }
});

userRouter.get("/e2ee/prekeys/count", async (req, res, next) => {
  try {
    const count = await e2eeService.remainingPreKeys(authed(req).sub);
    ok(res, { remaining: count });
  } catch (err) {
    next(err);
  }
});
