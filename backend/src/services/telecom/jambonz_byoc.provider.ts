// Jambonz BYOC provider — implements ITelephonyProvider against the pinned
// self-hosted jambonz 0.x REST API. API facts verified against the published
// jambonz docs (REST Call Control > Calls):
//   POST   {apiBase}/v1/Accounts/{AccountSid}/Calls          -> 201 { sid }
//   GET    {apiBase}/v1/Accounts/{AccountSid}/Calls/{sid}    -> 200 { call_status, duration }
//   DELETE {apiBase}/v1/Accounts/{AccountSid}/Calls/{sid}    -> 204 (hangup)
//   Auth:  Authorization: Bearer {token}
// Webhooks use either HTTP basic auth (self-hosted) or the Jambonz-Signature
// header (HMAC of the raw payload with the webhook secret) — see
// https://docs.jambonz.org/guides/features/securing-http-endpoints.
//
// Codec note: the lowBitrate flag (opus_bitrate=20000 + SILK) is FreeSWITCH-leg
// ONLY and is intentionally ignored here — jambonz negotiates codecs itself.

import { createHmac, timingSafeEqual } from "node:crypto";
import { env } from "../../config/env.js";
import { logger } from "../../lib/logger.js";
import { CircuitBreaker } from "./circuit-breaker.js";
import { normalizeE164 } from "./numbers.js";
import type { CallStatusResult, CdrStatus, ITelephonyProvider, OutboundCallRequest, OutboundCallResult } from "./types.js";

const REQUEST_TIMEOUT_MS = 8_000;

export class JambonzByocProvider implements ITelephonyProvider {
  readonly providerId = "JAMBONZ" as const;

  private readonly breaker = new CircuitBreaker({ name: "jambonz" });

  static isConfigured(): boolean {
    return (
      env.JAMBONZ_API_BASE_URL.length > 0 &&
      env.JAMBONZ_ACCOUNT_SID.length > 0 &&
      env.JAMBONZ_API_TOKEN.length > 0
    );
  }

  /** {apiBase}/v1/Accounts/{AccountSid}/Calls */
  private callsEndpoint(): string {
    return `${env.JAMBONZ_API_BASE_URL.replace(/\/$/, "")}/v1/Accounts/${env.JAMBONZ_ACCOUNT_SID}/Calls`;
  }

  async createOutboundCall(req: OutboundCallRequest): Promise<OutboundCallResult> {
    if (!JambonzByocProvider.isConfigured()) {
      throw new Error("JAMBONZ provider is not configured");
    }
    const to = normalizeE164(req.to);
    if (!to) throw new Error(`invalid destination number: ${req.to}`);
    const from = normalizeE164(req.from) ?? req.from;

    // The call_status_hook lets us learn terminal state for the CDR audit trail.
    // We deliberately omit `call_hook`/`application_sid`: these outbound legs are
    // pure terminations that the FS/mesh layer bridges into. Application-layer
    // voice control (interpreter execution) would be answered at the separate
    // /api/cpaas/webhook/call endpoint when an app leg is assigned.
    const callStatusUrl = `${this.callbackBase()}/api/cpaas/webhook/call-status`;
    const callHookAuth = this.webhookBasicAuth();

    return this.breaker.execute(async () => {
      const res = await fetch(this.callsEndpoint(), {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.JAMBONZ_API_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from,
          to: {
            type: "phone",
            number: to,
            ...(env.JAMBONZ_CARRIER ? { trunk: env.JAMBONZ_CARRIER } : {}),
          },
          call_status_hook: {
            url: callStatusUrl,
            method: "post",
            ...callHookAuth,
          },
          timeout: req.timeoutSec ?? 60,
          timeLimit: req.maxDurationSec,
          answerOnBridge: true,
          ...(req.clientRef ? { tag: { clientRef: req.clientRef, meshHops: req.meshHops ?? 0 } } : {}),
        }),
        signal: this.abortSignal(),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        throw new Error(`jambonz create call failed: ${res.status} ${text.slice(0, 300)}`);
      }
      const body = (await res.json()) as { sid?: string };
      if (!body.sid) {
        throw new Error("jambonz create call returned no sid");
      }
      return { callSid: body.sid, status: "QUEUED", gatewayType: "JAMBONZ" };
    });
  }

  async getCallStatus(callSid: string): Promise<CallStatusResult> {
    return this.breaker.execute(async () => {
      const res = await fetch(`${this.callsEndpoint()}/${encodeURIComponent(callSid)}`, {
        method: "GET",
        headers: { Authorization: `Bearer ${env.JAMBONZ_API_TOKEN}` },
        signal: this.abortSignal(),
      });
      if (!res.ok) throw new Error(`jambonz get call failed: ${res.status}`);
      const body = (await res.json()) as {
        call_status?: string;
        duration?: number;
        direction?: string;
        from?: string;
        to?: string;
      };
      return {
        callSid,
        status: mapJambonzStatus(body.call_status),
        durationSec: body.duration,
        gatewayType: "JAMBONZ",
      };
    });
  }

  async endCall(callSid: string): Promise<void> {
    await this.breaker.execute(async () => {
      const res = await fetch(`${this.callsEndpoint()}/${encodeURIComponent(callSid)}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${env.JAMBONZ_API_TOKEN}` },
        signal: this.abortSignal(),
      });
      if (res.status !== 204 && !res.ok) {
        throw new Error(`jambonz delete call failed: ${res.status}`);
      }
    });
  }

  /**
   * Validates an inbound webhook. Prefers HTTP basic auth (the self-hosted
   * mechanism); if a signing secret is configured, falls back to verifying the
   * Jambonz-Signature HMAC over the raw body.
   */
  validateWebhook(headers: Record<string, string | undefined>, rawBody: string): boolean {
    if (env.JAMBONZ_WEBHOOK_USERNAME && env.JAMBONZ_WEBHOOK_PASSWORD) {
      const expected = `Basic ${Buffer.from(`${env.JAMBONZ_WEBHOOK_USERNAME}:${env.JAMBONZ_WEBHOOK_PASSWORD}`).toString("base64")}`;
      const actual = headers["authorization"] ?? headers["Authorization"] ?? "";
      if (safeEqual(expected, actual)) return true;
    }
    if (env.JAMBONZ_WEBHOOK_SECRET) {
      const signature = headers["jambonz-signature"] ?? headers["Jambonz-Signature"];
      if (signature) {
        const digest = createHmac("sha256", env.JAMBONZ_WEBHOOK_SECRET).update(rawBody).digest("hex");
        const digestB64 = createHmac("sha256", env.JAMBONZ_WEBHOOK_SECRET).update(rawBody).digest("base64");
        if (safeEqual(digest, signature) || safeEqual(digestB64, signature)) return true;
      }
    }
    logger.warn("rejected jambonz webhook: no valid auth present");
    return false;
  }

  private callbackBase(): string {
    return env.JAMBONZ_CALLBACK_BASE_URL.replace(/\/$/, "");
  }

  private webhookBasicAuth(): { username?: string; password?: string } {
    if (env.JAMBONZ_WEBHOOK_USERNAME && env.JAMBONZ_WEBHOOK_PASSWORD) {
      return { username: env.JAMBONZ_WEBHOOK_USERNAME, password: env.JAMBONZ_WEBHOOK_PASSWORD };
    }
    return {};
  }

  private abortSignal(): AbortSignal {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    timer.unref?.();
    return controller.signal;
  }
}

/** Convert jambonz lowercase call statuses onto the platform CDR status set. */
export function mapJambonzStatus(status: string | undefined): CdrStatus {
  switch (status) {
    case "trying":
    case "ringing":
    case "alerting":
      return "RINGING";
    case "in-progress":
      return "IN_PROGRESS";
    case "queued":
      return "QUEUED";
    case "completed":
      return "COMPLETED";
    case "busy":
      return "BUSY";
    case "no-answer":
      return "NO_ANSWER";
    case "failed":
      return "FAILED";
    default:
      return "QUEUED";
  }
}

function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export const jambonzProvider = new JambonzByocProvider();
