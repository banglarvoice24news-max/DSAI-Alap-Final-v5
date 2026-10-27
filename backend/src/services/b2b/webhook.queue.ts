import { redis } from "../../lib/redis.js";
import { logger } from "../../lib/logger.js";
import type { B2bWebhookEvent } from "./webhook.dispatcher.js";

const PENDING_PREFIX = "b2b:webhooks:pending";
const MAX_PENDING_PER_TENANT = 1000;
const MAX_ATTEMPTS = 6;
const BATCH_PER_TENANT = 5;
const RETRY_INTERVAL_MS = 60_000;

export interface PendingWebhook extends B2bWebhookEvent {
  webhookUrl: string;
  attempts: number;
}

function pendingKey(tenantId: string): string {
  return `${PENDING_PREFIX}:${tenantId}`;
}

export async function enqueueWebhook(event: B2bWebhookEvent, webhookUrl: string): Promise<void> {
  try {
    const pending: PendingWebhook = { ...event, webhookUrl, attempts: 0 };
    const key = pendingKey(event.tenantId);
    await redis.rpush(key, JSON.stringify(pending));
    await redis.ltrim(key, -MAX_PENDING_PER_TENANT, -1);
  } catch (err) {
    logger.error({ err, tenant: event.tenantId }, "b2b webhook enqueue failed");
  }
}

export type WebhookDeliver = (event: B2bWebhookEvent, webhookUrl: string) => Promise<boolean>;

export async function retryPendingWebhooksOnce(deliver: WebhookDeliver): Promise<void> {
  const keys = await redis.keys(`${PENDING_PREFIX}:*`).catch((err) => {
    logger.error({ err }, "b2b webhook retry key scan failed");
    return [] as string[];
  });
  for (const key of keys) {
    for (let i = 0; i < BATCH_PER_TENANT; i++) {
      const raw = await redis.lpop(key).catch(() => null);
      if (!raw) break;
      let pending: PendingWebhook;
      try {
        pending = JSON.parse(raw) as PendingWebhook;
      } catch {
        logger.error({ tenant: key }, "b2b webhook pending entry unparsable");
        continue;
      }
      pending.attempts += 1;
      const delivered = await deliver(pending, pending.webhookUrl);
      if (delivered) {
        logger.info(
          { tenant: pending.tenantId, type: pending.type, attempts: pending.attempts },
          "b2b webhook delivered on retry",
        );
      } else if (pending.attempts >= MAX_ATTEMPTS) {
        logger.warn(
          { tenant: pending.tenantId, type: pending.type, attempts: pending.attempts },
          "b2b webhook dead-lettered after max attempts",
        );
      } else {
        await redis.rpush(key, JSON.stringify(pending)).catch(() => undefined);
      }
    }
  }
}

export function startWebhookRetryLoop(deliver: WebhookDeliver): NodeJS.Timeout {
  const timer = setInterval(() => {
    void retryPendingWebhooksOnce(deliver);
  }, RETRY_INTERVAL_MS);
  timer.unref();
  return timer;
}
