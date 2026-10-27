// CPaaS router — mounted at /api/cpaas ONLY when env.ENABLE_CPAAS_LAYER is true
// (see app.ts). Business endpoints sit behind hashed Prisma ApiKey auth
// (x-dsaialap-key). Provider webhooks are registered BEFORE the key gate and
// authenticate with the provider's own basic-auth / signature mechanism.

import { randomUUID } from "node:crypto";
import { Router } from "express";
import type { Request } from "express";
import { z } from "zod";
import type { CdrStatus } from "@prisma/client";
import { env } from "../../config/env.js";
import { redis } from "../../lib/redis.js";
import { ok, AppError } from "../../lib/http.js";
import { requireCpaasKey } from "./cpaas-key.service.js";
import {
  failoverProvider,
  updateDlr,
  getDlr,
  linkJasminMessageId,
  resolveJasminMessageId,
} from "../../services/telecom/sms_gateway.service.js";
import { JambonzByocProvider, jambonzProvider, mapJambonzStatus } from "../../services/telecom/jambonz_byoc.provider.js";
import { eslClient } from "../../services/telecom/freeswitch_esl.service.js";
import { cdrService } from "../../services/telecom/cdr.service.js";
import { gsmPolicyService } from "../../services/telecom/gsm-policy.service.js";
import { normalizeE164 } from "../../services/telecom/numbers.js";
import { AlapVoiceResponse } from "../../services/telecom/voice_interpreter.service.js";
import type { CpaasCallEvent } from "../../services/telecom/types.js";

export const cpaasRouter = Router();

// ---------------------------------------------------------------------------
// Provider webhooks (no x-dsaialap-key; they authenticate via basic auth)
// ---------------------------------------------------------------------------

/**
 * jambonz new-call webhook. Voice-application legs are answered here. While
 * outbound legs are pure terminations bridged by the FS/mesh layer this returns
 * an empty verb document; application voice flows will populate it via the
 * voice interpreter in a later phase.
 */
cpaasRouter.post("/webhook/call", (req, res) => {
  const valid = jambonzProvider.validateWebhook(headersOf(req), rawBodyOf(req));
  if (!valid) {
    res.status(401).json({ ok: false, error: { code: "CPAAS_WEBHOOK_UNAUTHORIZED" } });
    return;
  }
  res.json(new AlapVoiceResponse().toJSON());
});

/** jambonz call_status_hook — feed terminal status into the CDR trail. */
cpaasRouter.post("/webhook/call-status", async (req, res, next) => {
  try {
    const valid = jambonzProvider.validateWebhook(headersOf(req), rawBodyOf(req));
    if (!valid) {
      res.status(401).json({ ok: false, error: { code: "CPAAS_WEBHOOK_UNAUTHORIZED" } });
      return;
    }
    const body = z
      .object({
        call_sid: z.string().min(1),
        call_status: z.string().min(1),
        duration: z.number().int().nonnegative().optional(),
        from: z.string().optional(),
        to: z.string().optional(),
      })
      .parse(req.body ?? {});
    const event = mapStatusToEvent(body.call_sid, body.call_status, body.duration, body.from, body.to);
    if (event) {
      await redis.publish(env.CPAAS_CALL_EVENTS_CHANNEL, JSON.stringify(event));
    }
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** Jasmin DLR receipt. Must be acked with the literal body "ACK/Jasmin". */
cpaasRouter.post("/webhook/jasmin/dlr", async (req, res) => {
  res.type("text/plain");
  const id = typeof req.body?.id === "string" ? req.body.id : "";
  const messageStatus = typeof req.body?.message_status === "string" ? req.body.message_status : "";
  try {
    const refId = await resolveJasminMessageId(id);
    if (refId) {
      const delivered = /ROK|DELIVRD/i.test(messageStatus);
      const failed = /(ERR|UNDELIV|REJECT|EXPIRED)/i.test(messageStatus);
      await updateDlr(refId, { status: delivered ? "DELIVERED" : failed ? "FAILED" : "SENT" });
    }
  } catch (err) {
    // We still ack so Jasmin stops retrying; the failure is logged.
    void err;
  }
  res.send("ACK/Jasmin");
});

/** Inbound webhook validator used by operators to confirm provider auth works. */
cpaasRouter.post("/webhook/validate", (req, res) => {
  const valid = jambonzProvider.validateWebhook(headersOf(req), rawBodyOf(req));
  res.json({ ok: valid });
});

// ---------------------------------------------------------------------------
// Business endpoints (x-dsaialap-key authenticated)
// ---------------------------------------------------------------------------

cpaasRouter.use(requireCpaasKey);

const createCallSchema = z.object({
  to: z.string().min(7).max(20),
  from: z.string().min(7).max(20).optional(),
  gateway: z.enum(["GSM", "JAMBONZ"]).optional(),
  lowBitrate: z.boolean().optional(),
  meshHops: z.number().int().min(0).max(16).optional(),
  consent: z.boolean().optional(),
  clientRef: z.string().max(128).optional(),
});

cpaasRouter.post("/calls", async (req, res, next) => {
  try {
    const input = createCallSchema.parse(req.body ?? {});
    const to = normalizeE164(input.to);
    const from = input.from ? normalizeE164(input.from) : null;
    if (!to) throw new AppError(400, "invalid destination number", "CPAAS_INVALID_NUMBER");
    if (!from) throw new AppError(400, "an originating number (from) is required", "CPAAS_FROM_REQUIRED");

    const requested = input.gateway ?? (gsmPreferred(input.consent) ? "GSM" : "JAMBONZ");
    const decision = await gsmPolicyService.decideTermination({
      from,
      to,
      requestedGateway: requested,
      licensedFallback: "JAMBONZ",
    });

    if (decision.gateway === "BLOCKED") {
      throw new AppError(403, decision.reason, "CPAAS_TERMINATION_BLOCKED");
    }

    const callSid = randomUUID();
    const lowBitrate = input.lowBitrate ?? false;

    if (decision.gateway === "GSM") {
      // §5 BTRC comment: owner-personal, consent-gated, BD-only GSM leg.
      if (!decision.sim) throw new AppError(403, "GSM path requires a registered SIM", "CPAAS_SIM_REQUIRED");
      eslClient.start();
      await eslClient.makeOutboundCall({
        callSid,
        to,
        from: decision.sim.ownerNumber,
        gatewayType: "GSM",
        lowBitrate,
        timeoutSec: 45,
      });
      ok(res, { callSid, gatewayType: "GSM", status: "QUEUED", lowBitrate }, 202);
      return;
    }

    // Licensed voice termination (jambonz BYOC / IGW).
    const provider = ensureJambonz();
    const result = await provider.createOutboundCall({
      to,
      from,
      lowBitrate,
      clientRef: input.clientRef,
      meshHops: input.meshHops,
      consentFlag: input.consent ?? false,
      timeoutSec: 45,
    });
    ok(res, { callSid: result.callSid, gatewayType: "JAMBONZ", status: result.status, lowBitrate }, 202);
  } catch (err) {
    next(err);
  }
});

const sendSmsSchema = z.object({
  to: z.string().min(7).max(20),
  from: z.string().min(7).max(20).optional(),
  body: z.string().min(1).max(1600),
  consent: z.boolean().optional(),
});

cpaasRouter.post("/sms", async (req, res, next) => {
  try {
    const input = sendSmsSchema.parse(req.body ?? {});
    const to = normalizeE164(input.to);
    if (!to) throw new AppError(400, "invalid destination number", "CPAAS_INVALID_NUMBER");
    const refId = randomUUID();
    const consentFlag = input.consent === true;

    const result = await failoverProvider.send({
      to,
      from: input.from ? normalizeE164(input.from) ?? input.from : undefined,
      body: input.body,
      consentFlag,
      refId,
    });

    if (result.providerId === "JASMIN" && result.messageId) {
      await linkJasminMessageId(result.messageId, refId);
    }
    const dlr = await getDlr(refId);
    ok(
      res,
      {
        refId,
        provider: result.providerId,
        status: dlr?.status ?? (result.accepted ? "QUEUED" : "FAILED"),
        consentFlag,
      },
      202,
    );
  } catch (err) {
    next(err);
  }
});

const logsSchema = z.object({
  gatewayType: z.enum(["MESH", "VOIP", "GSM", "JASMIN", "JAMBONZ"]).optional(),
  status: z.string().optional(),
  to: z.string().optional(),
  from: z.string().optional(),
  since: z.string().datetime({ offset: true }).optional(),
  until: z.string().datetime({ offset: true }).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
  offset: z.coerce.number().int().min(0).optional(),
});

cpaasRouter.get("/logs", async (req, res, next) => {
  try {
    const query = logsSchema.parse(req.query);
    const rows = await cdrService.listForAudit({
      gatewayType: query.gatewayType,
      status: query.status as CdrStatus | undefined,
      to: query.to,
      from: query.from,
      since: query.since,
      until: query.until,
      limit: query.limit,
      offset: query.offset,
    });
    ok(res, { count: rows.length, logs: rows });
  } catch (err) {
    next(err);
  }
});

cpaasRouter.get("/calls/:id/status", async (req, res, next) => {
  try {
    const callSid = req.params.id;
    const live = await cdrService.getLiveStatus(callSid);
    const row = live ?? (await cdrService.findByCallSid(callSid));
    if (!row) {
      throw new AppError(404, "call not found", "CPAAS_CALL_NOT_FOUND");
    }
    ok(res, { callSid, ...(typeof row === "object" && row !== null ? (row as object) : { status: row }) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function gsmPreferred(consent: boolean | undefined): boolean {
  // Only prefer the GSM path when the caller has explicitly asserted consent.
  return consent === true;
}

function ensureJambonz(): JambonzByocProvider {
  if (!JambonzByocProvider.isConfigured()) {
    throw new AppError(503, "licensed voice gateway is not configured", "CPAAS_LICENSED_GATEWAY_UNAVAILABLE");
  }
  return jambonzProvider;
}

/** Translate a jambonz call_status_hook payload into a call event on the shared channel. */
function mapStatusToEvent(
  callSid: string,
  callStatus: string,
  duration?: number,
  from?: string,
  to?: string,
): CpaasCallEvent | null {
  const status = mapJambonzStatus(callStatus);
  if (status === "QUEUED" || status === "RINGING") return null;
  const type = ((): CpaasCallEvent["type"] => {
    switch (status) {
      case "IN_PROGRESS":
        return "call.answered";
      case "COMPLETED":
        return "call.ended";
      case "NO_ANSWER":
        return "call.no_answer";
      case "BUSY":
        return "call.busy";
      default:
        return "call.failed";
    }
  })();
  return {
    type,
    callSid,
    direction: "OUTBOUND",
    from: from ?? "",
    to: to ?? "",
    gatewayType: "JAMBONZ",
    status,
    durationSec: duration,
    occurredAt: new Date().toISOString(),
  };
}

function headersOf(req: Request): Record<string, string | undefined> {
  return req.headers as Record<string, string | undefined>;
}

function rawBodyOf(req: Request): string {
  const raw = (req as Request & { rawBody?: string }).rawBody;
  return raw ?? JSON.stringify(req.body ?? {});
}
