import { Router } from "express";
import { z } from "zod";
import { ok } from "../../lib/http.js";
import { authed, requireAuth } from "../../middleware/auth.js";
import { messageService } from "./message.service.js";

export const messageRouter = Router();
messageRouter.use(requireAuth);

messageRouter.get("/", async (req, res, next) => {
  try {
    const query = z
      .object({
        cursor: z.string().optional(),
        take: z.coerce.number().int().min(1).max(100).optional(),
      })
      .parse(req.query);
    const messages = await messageService.inbox(
      authed(req).sub,
      query.cursor,
      query.take,
    );
    ok(res, messages);
  } catch (err) {
    next(err);
  }
});

/**
 * Per-counterpart chat list summaries. Returns only metadata (who, when,
 * unread count) — never plaintext; bodies stay end-to-end encrypted.
 */
messageRouter.get("/threads", async (req, res, next) => {
  try {
    const query = z
      .object({ take: z.coerce.number().int().min(1).max(100).optional() })
      .parse(req.query);
    ok(res, await messageService.threads(authed(req).sub, query.take));
  } catch (err) {
    next(err);
  }
});

messageRouter.post("/", async (req, res, next) => {
  try {
    const body = z
      .object({
        receiverId: z.string().uuid(),
        ciphertext: z.string().min(1),
        nonce: z.string().optional(),
        header: z.string().optional(),
      })
      .parse(req.body);
    const stored = await messageService.storeEncrypted({
      senderId: authed(req).sub,
      ...body,
    });
    ok(res, stored, 201);
  } catch (err) {
    next(err);
  }
});
