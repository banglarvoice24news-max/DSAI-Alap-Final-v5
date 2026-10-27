// SMS gateway service — ISmsProvider implementations and the BD failover router.
//
// Providers:
//   - JasminProvider     : licensed SMPP gateway via the Jasmin HTTP API (0.10.x).
//                          Wire format verified against docs.jasminsms.com: POST
//                          {base}/send with form params username/password/to/from/
//                          content/dlr*; success returns the message-id as plain
//                          text; DLR receipts must be acked with body "ACK/Jasmin".
//   - AndroidGsmProvider : the §5 personal GSM relay (companion app on the SIM
//                          owner's own device, paired over ADB). Only ever used
//                          for the owner's personal, on-net, BD traffic.
//
// FailoverProvider routes BD (880-prefix) numbers to the Android GSM relay when
// the §5 policy allows it AND per-device quota remains, otherwise to Jasmin.
// Every send is:
//   * rate-limited per device (Redis fixed-window counters);
//   * DLR-tracked via Redis (per refId);
//   * tagged with the §5 consent flag (recorded on the DLR record + payload).
//
// BTRC COMPLIANCE COMMENT (§5): this is the only path where a personal SIM may
// carry SMS. It is gated by gsmPolicyService so only the SIM owner's own
// Bangladeshi traffic ever touches it. Commercial / international traffic is
// Jasmin (licensed) or refused.

import { env } from "../../config/env.js";
import { AppError } from "../../lib/http.js";
import { redis } from "../../lib/redis.js";
import { logger } from "../../lib/logger.js";
import { CircuitBreaker } from "./circuit-breaker.js";
import { gsmPolicyService } from "./gsm-policy.service.js";
import { isBangladeshNumber, normalizeE164 } from "./numbers.js";

export type SmsProviderId = "JASMIN" | "ANDROID_GSM";

export interface SmsMessage {
  /** Destination E.164 / national number. */
  to: string;
  /** Originating number. GSM legs MUST equal the registered SIM owner number. */
  from?: string;
  body: string;
  /** Explicit §5 consent flag; required for the Android GSM relay. */
  consentFlag: boolean;
  /** Caller-supplied correlation id. */
  refId: string;
}

export interface SmsResult {
  providerId: SmsProviderId;
  accepted: boolean;
  messageId?: string;
}

export interface ISmsProvider {
  readonly providerId: SmsProviderId;
  isConfigured(): boolean;
  send(msg: SmsMessage): Promise<SmsResult>;
}

const REQUEST_TIMEOUT_MS = 8_000;
export const DLR_TTL_SECONDS = 7 * 24 * 60 * 60;

export class SmsUnroutableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SmsUnroutableError";
  }
}

// ---------------------------------------------------------------------------
// Jasmin (licensed SMPP gateway)
// ---------------------------------------------------------------------------

export class JasminProvider implements ISmsProvider {
  readonly providerId = "JASMIN" as const;
  private readonly breaker = new CircuitBreaker({ name: "jasmin" });

  isConfigured(): boolean {
    return env.JASMIN_HTTP_URL.length > 0 && env.JASMIN_HTTP_USERNAME.length > 0;
  }

  async send(msg: SmsMessage): Promise<SmsResult> {
    if (!this.isConfigured()) throw new SmsUnroutableError("JASMIN provider is not configured");
    const to = normalizeE164(msg.to) ?? msg.to;
    return this.breaker.execute(async () => {
      const form = new URLSearchParams({
        username: env.JASMIN_HTTP_USERNAME,
        password: env.JASMIN_HTTP_PASSWORD,
        to,
        content: msg.body,
        "dlr": "yes",
        "dlr-url": `${this.callbackBase()}/api/cpaas/webhook/jasmin/dlr`,
        "dlr-level": "2",
        "dlr-method": "POST",
      });
      if (msg.from) form.set("from", normalizeE164(msg.from) ?? msg.from);

      const res = await fetch(this.sendUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
        signal: abortSignal(),
      });
      const text = await res.text();
      if (!res.ok) {
        throw new Error(`jasmin send failed: ${res.status} ${text.slice(0, 300)}`);
      }
      return { providerId: "JASMIN", accepted: true, messageId: text.trim() || undefined };
    });
  }

  private sendUrl(): string {
    return `${env.JASMIN_HTTP_URL.replace(/\/$/, "")}/send`;
  }

  private callbackBase(): string {
    return env.DSAIALAP_PUBLIC_HOST.startsWith("http")
      ? env.DSAIALAP_PUBLIC_HOST
      : `https://${env.DSAIALAP_PUBLIC_HOST}`;
  }
}

// ---------------------------------------------------------------------------
// Android GSM relay (§5 personal path)
// ---------------------------------------------------------------------------

export class AndroidGsmProvider implements ISmsProvider {
  readonly providerId = "ANDROID_GSM" as const;
  private readonly breaker = new CircuitBreaker({ name: "android-gsm" });

  isConfigured(): boolean {
    return env.ANDROID_GSM_BASE_URL.length > 0 && env.ANDROID_GSM_TOKEN.length > 0;
  }

  async send(msg: SmsMessage): Promise<SmsResult> {
    if (!this.isConfigured()) throw new SmsUnroutableError("Android GSM relay is not configured");
    if (!msg.consentFlag) {
      // §5: never carry SMS over the personal SIM without explicit consent.
      throw new AppError(403, "consent flag is required for the GSM SMS path", "CPAAS_SMS_CONSENT_REQUIRED");
    }
    return this.breaker.execute(async () => {
      const res = await fetch(`${env.ANDROID_GSM_BASE_URL.replace(/\/$/, "")}/v1/sms`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${env.ANDROID_GSM_TOKEN}`,
        },
        body: JSON.stringify({
          to: normalizeE164(msg.to) ?? msg.to,
          from: msg.from ? (normalizeE164(msg.from) ?? msg.from) : undefined,
          body: msg.body,
          consentFlag: msg.consentFlag,
          refId: msg.refId,
        }),
        signal: abortSignal(),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        throw new Error(`android gsm send failed: ${res.status} ${text.slice(0, 300)}`);
      }
      return { providerId: "ANDROID_GSM", accepted: true, messageId: msg.refId };
    });
  }
}

// ---------------------------------------------------------------------------
// Per-device GSM SMS quota (Redis fixed-window counters)
// ---------------------------------------------------------------------------

export class GsmSmsQuota {
  async consume(deviceId: string): Promise<{ allowed: boolean; rpmRemaining: number; dailyRemaining: number }> {
    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    const rpmKey = `${env.CPAAS_REDIS_PREFIX}sms:rpm:${deviceId}`;
    const dayKey = `${env.CPAAS_REDIS_PREFIX}sms:daily:${deviceId}:${day}`;

    const [rpm, daily] = await Promise.all([
      incrementWindow(rpmKey, 60),
      incrementWindow(dayKey, 2 * 24 * 60 * 60),
    ]);
    const allowed = rpm <= env.CPAAS_SMS_GSM_MAX_RPM && daily <= env.CPAAS_SMS_GSM_DAILY_CAP;
    if (!allowed) {
      logger.warn(
        { deviceId, rpm, daily, rpmCap: env.CPAAS_SMS_GSM_MAX_RPM, dailyCap: env.CPAAS_SMS_GSM_DAILY_CAP },
        "gsm sms per-device quota exceeded",
      );
    }
    return {
      allowed,
      rpmRemaining: Math.max(env.CPAAS_SMS_GSM_MAX_RPM - rpm, 0),
      dailyRemaining: Math.max(env.CPAAS_SMS_GSM_DAILY_CAP - daily, 0),
    };
  }
}

async function incrementWindow(key: string, ttlSeconds: number): Promise<number> {
  const count = await redis.incr(key);
  if (count === 1) {
    await redis.expire(key, ttlSeconds);
  }
  return count;
}

// ---------------------------------------------------------------------------
// Failover provider — BD-first-to-Android, else Jasmin
// ---------------------------------------------------------------------------

export class FailoverProvider {
  constructor(
    private readonly android: AndroidGsmProvider = new AndroidGsmProvider(),
    private readonly jasmin: JasminProvider = new JasminProvider(),
    private readonly quota: GsmSmsQuota = new GsmSmsQuota(),
  ) {}

  /**
   * Route and send one SMS. BD numbers may use the Android GSM relay when the
   * §5 policy approves (owner + consent + BD-only) and per-device quota allows;
   * otherwise the message goes to Jasmin (licensed). Non-BD traffic never
   * touches the GSM relay.
   */
  async send(msg: SmsMessage): Promise<SmsResult> {
    const deviceId = env.ANDROID_GSM_DEVICE_ID;
    const canUseGsmRelay =
      this.android.isConfigured() &&
      deviceId.length > 0 &&
      isBangladeshNumber(msg.to) &&
      (await this.gsmPolicyAllows(msg));

    if (canUseGsmRelay) {
      const quota = await this.quota.consume(deviceId);
      if (quota.allowed) {
        const result = await this.android.send(msg);
        if (result.accepted) await trackDlr(msg, "ANDROID_GSM", result.messageId);
        return result;
      }
      logger.warn({ refId: msg.refId }, "gsm sms quota reached; falling back to Jasmin");
    }

    if (this.jasmin.isConfigured()) {
      const result = await this.jasmin.send(msg);
      if (result.accepted) await trackDlr(msg, "JASMIN", result.messageId);
      return result;
    }

    throw new SmsUnroutableError("no SMS provider available for this message");
  }

  private async gsmPolicyAllows(msg: SmsMessage): Promise<boolean> {
    if (!msg.from) return false;
    const decision = await gsmPolicyService.decideTermination({
      from: msg.from,
      to: msg.to,
      requestedGateway: "GSM",
      licensedFallback: "JASMIN",
    });
    return decision.gateway === "GSM";
  }
}

export const jasminProvider = new JasminProvider();
export const androidGsmProvider = new AndroidGsmProvider();
export const failoverProvider = new FailoverProvider();

// ---------------------------------------------------------------------------
// DLR tracking (Redis)
// ---------------------------------------------------------------------------

export interface DlrRecord {
  refId: string;
  to: string;
  from?: string;
  provider: SmsProviderId;
  status: "QUEUED" | "SENT" | "DELIVERED" | "FAILED";
  consentFlag: boolean;
  messageId?: string;
  updatedAt: string;
}

export async function trackDlr(msg: SmsMessage, provider: SmsProviderId, messageId?: string): Promise<void> {
  const record: DlrRecord = {
    refId: msg.refId,
    to: msg.to,
    from: msg.from,
    provider,
    status: "QUEUED",
    consentFlag: msg.consentFlag,
    messageId,
    updatedAt: new Date().toISOString(),
  };
  await redis.set(dlrKey(msg.refId), JSON.stringify(record), "EX", DLR_TTL_SECONDS);
}

export async function getDlr(refId: string): Promise<DlrRecord | null> {
  const raw = await redis.get(dlrKey(refId));
  if (!raw) return null;
  try {
    return JSON.parse(raw) as DlrRecord;
  } catch {
    return null;
  }
}

export async function updateDlr(refId: string, patch: Partial<DlrRecord>): Promise<DlrRecord | null> {
  const current = await getDlr(refId);
  if (!current) return null;
  const updated: DlrRecord = { ...current, ...patch, updatedAt: new Date().toISOString() };
  await redis.set(dlrKey(refId), JSON.stringify(updated), "EX", DLR_TTL_SECONDS);
  return updated;
}

export async function linkJasminMessageId(jasminMessageId: string, refId: string): Promise<void> {
  await redis.set(`${env.CPAAS_REDIS_PREFIX}sms:jasmin:${jasminMessageId}`, refId, "EX", DLR_TTL_SECONDS);
}

export async function resolveJasminMessageId(jasminMessageId: string): Promise<string | null> {
  return redis.get(`${env.CPAAS_REDIS_PREFIX}sms:jasmin:${jasminMessageId}`);
}

function dlrKey(refId: string): string {
  return `${env.CPAAS_REDIS_PREFIX}sms:dlr:${refId}`;
}

function abortSignal(): AbortSignal {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  timer.unref?.();
  return controller.signal;
}
