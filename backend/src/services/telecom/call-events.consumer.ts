// CallEventConsumer — subscribes to the dedicated `call:events:cpaas` pubsub
// channel and (a) refreshes the live call-status view in Redis, and (b) writes
// terminal events into the append-only CDR audit trail. This is the ONLY place
// that consumes that channel; it is started in index.ts when the CPaaS layer is
// enabled. Uses its own Redis connection because ioredis subscribers must not
// share the client that also issues commands.

import Redis from "ioredis";
import { env } from "../../config/env.js";
import { logger } from "../../lib/logger.js";
import { cdrService } from "./cdr.service.js";
import type { CpaasCallEvent, CdrStatus } from "./types.js";

const TERMINAL: CdrStatus[] = ["COMPLETED", "FAILED", "BUSY", "NO_ANSWER", "CANCELED"];

export class CallEventConsumer {
  private subscriber: Redis | null = null;

  async start(): Promise<void> {
    if (this.subscriber) return;
    const sub = new Redis(env.REDIS_URL, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
    });
    this.subscriber = sub;
    sub.on("error", (err) => logger.error({ err }, "cpaas call event subscriber error"));
    await sub.subscribe(env.CPAAS_CALL_EVENTS_CHANNEL);
    sub.on("message", (_channel: string, raw: string) => {
      void this.handle(raw).catch((err) => {
        logger.error({ err }, "cpaas call event consumer handler failed");
      });
    });
    logger.info({ channel: env.CPAAS_CALL_EVENTS_CHANNEL }, "cpaas call event consumer started");
  }

  async stop(): Promise<void> {
    const sub = this.subscriber;
    this.subscriber = null;
    if (!sub) return;
    await sub.unsubscribe().catch(() => undefined);
    await sub.quit().catch(() => undefined);
  }

  private async handle(raw: string): Promise<void> {
    let event: CpaasCallEvent;
    try {
      event = JSON.parse(raw) as CpaasCallEvent;
    } catch {
      logger.error({ raw: raw.slice(0, 200) }, "cpaas call event unparsable; dropped");
      return;
    }
    if (!event.callSid || !event.status || !event.type) {
      logger.warn({ event }, "cpaas call event missing required fields; dropped");
      return;
    }

    await cdrService.setLiveStatus(event.callSid, event.status, {
      type: event.type,
      gatewayType: event.gatewayType,
      durationSec: event.durationSec,
    });

    if (TERMINAL.includes(event.status)) {
      const input = cdrService.toCdrInput(event);
      if (!input) return;
      const created = await cdrService.record(input);
      if (created) {
        logger.info({ callSid: event.callSid, status: event.status }, "cpaas cdr recorded");
      } else {
        // Append-only invariant: a duplicate callSid means the trail already has
        // this leg. We never overwrite it.
        logger.debug({ callSid: event.callSid }, "cpaas cdr duplicate skipped");
      }
    }
  }
}

export const callEventConsumer = new CallEventConsumer();

