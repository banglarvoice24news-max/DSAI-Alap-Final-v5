import { Router } from "express";
import { z } from "zod";
import { ok } from "../../lib/http.js";
import { b2bTenant, requireB2bKey } from "../../middlewares/b2b-auth.js";
import { webhookDispatcher } from "../../services/b2b/webhook.dispatcher.js";

export const b2bRouter = Router();
b2bRouter.use(requireB2bKey);

b2bRouter.get("/v1/health", (req, res) => {
  const tenant = b2bTenant(req);
  ok(res, {
    service: "dsaialap-b2b",
    tenant: tenant.name,
    tier: tenant.tier,
    rpm: tenant.rpm,
  });
});

b2bRouter.get("/v1/me", (req, res) => {
  const tenant = b2bTenant(req);
  ok(res, {
    id: tenant.id,
    name: tenant.name,
    tier: tenant.tier,
    rpm: tenant.rpm,
    webhookConfigured: Boolean(tenant.webhookUrl),
  });
});

b2bRouter.post("/v1/webhooks/test", async (req, res, next) => {
  try {
    const tenant = b2bTenant(req);
    const delivered = await webhookDispatcher.dispatch(tenant, {
      type: "b2b.webhook.test",
      payload: { ping: true },
    });
    ok(res, { delivered, webhookConfigured: Boolean(tenant.webhookUrl) });
  } catch (err) {
    next(err);
  }
});

b2bRouter.post("/v1/events", async (req, res, next) => {
  try {
    const body = z
      .object({
        type: z.string().min(3).max(64),
        payload: z.record(z.unknown()).default({}),
      })
      .parse(req.body);
    const tenant = b2bTenant(req);
    const delivered = await webhookDispatcher.dispatch(
      tenant,
      {
        type: body.type,
        payload: body.payload,
      },
      { queueOnFailure: true },
    );
    ok(res, { accepted: true, delivered, queued: !delivered && Boolean(tenant.webhookUrl) }, 202);
  } catch (err) {
    next(err);
  }
});
