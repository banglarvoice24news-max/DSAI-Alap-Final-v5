import { logger } from "../../lib/logger.js";
import { enqueueWebhook } from "./webhook.queue.js";
import type { B2bTenant } from "./b2b-key.service.js";

export interface B2bWebhookEvent {
  type: string;
  occurredAt: string;
  tenantId: string;
  payload: Record<string, unknown>;
}

export interface DispatchOptions {
  queueOnFailure?: boolean;
}

export class WebhookDispatcher {
  async deliver(event: B2bWebhookEvent, webhookUrl: string): Promise<boolean> {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 2500);
      const res = await fetch(webhookUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Dsaialap-Event": event.type,
          "X-Dsaialap-Tenant": event.tenantId,
        },
        body: JSON.stringify(event),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (!res.ok) {
        logger.warn({ status: res.status, tenant: event.tenantId }, "b2b webhook non-2xx");
        return false;
      }
      return true;
    } catch (err) {
      logger.warn({ err, tenant: event.tenantId }, "b2b webhook dispatch failed");
      return false;
    }
  }

  async dispatch(
    tenant: B2bTenant,
    event: Omit<B2bWebhookEvent, "tenantId" | "occurredAt">,
    options: DispatchOptions = {},
  ): Promise<boolean> {
    if (!tenant.webhookUrl) return false;
    const body: B2bWebhookEvent = {
      type: event.type,
      payload: event.payload,
      tenantId: tenant.id,
      occurredAt: new Date().toISOString(),
    };
    const delivered = await this.deliver(body, tenant.webhookUrl);
    if (!delivered && options.queueOnFailure) {
      await enqueueWebhook(body, tenant.webhookUrl);
    }
    return delivered;
  }
}

export const webhookDispatcher = new WebhookDispatcher();
