// CDR (Call Detail Record) service.
//
// The CDR table is the IMMUTABLE audit trail required by §5: rows are written
// once with createMany(... skipDuplicates) and never updated in code. Replays
// of the same event are dropped on the unique callSid, so the trail cannot be
// rewritten by duplicate gateway events.

import { prisma } from "../../lib/prisma.js";
import { redis } from "../../lib/redis.js";
import type {
  CdrDirection,
  CdrStatus,
  GatewayType,
} from "@prisma/client";
import { env } from "../../config/env.js";
import type { CpaasCallEvent } from "./types.js";

export interface NewCdrInput {
  callSid: string;
  clientRef?: string;
  direction: CdrDirection;
  from: string;
  to: string;
  gatewayType: GatewayType;
  status: CdrStatus;
  consentFlag?: boolean;
  durationSec?: number;
  costMicros?: number;
  meshHops?: number;
  bitrate?: number;
  jitterMs?: number;
  packetLossPct?: number;
}

export interface CdrQuery {
  from?: string;
  to?: string;
  gatewayType?: GatewayType;
  status?: CdrStatus;
  since?: string;
  until?: string;
  limit?: number;
  offset?: number;
}

function statusKey(callSid: string): string {
  return `${env.CPAAS_REDIS_PREFIX}call:status:${callSid}`;
}

export class CdrService {
  /** Append-only insert. Returns false when the callSid already exists (replay). */
  async record(input: NewCdrInput): Promise<boolean> {
    const created = await prisma.cdr.createMany({
      data: [
        {
          callSid: input.callSid,
          clientRef: input.clientRef,
          direction: input.direction,
          fromNumber: input.from,
          toNumber: input.to,
          gatewayType: input.gatewayType,
          status: input.status,
          consentFlag: input.consentFlag ?? false,
          durationSec: input.durationSec ?? 0,
          costMicros: input.costMicros ?? 0,
          meshHops: input.meshHops,
          bitrate: input.bitrate,
          jitterMs: input.jitterMs,
          packetLossPct: input.packetLossPct,
        },
      ],
      skipDuplicates: true,
    });
    return created.count === 1;
  }

  async query(query: CdrQuery): Promise<Array<{ callSid: string; createdAt: Date }>> {
    return prisma.cdr.findMany({
      where: {
        fromNumber: query.from,
        toNumber: query.to,
        gatewayType: query.gatewayType,
        status: query.status,
        createdAt: {
          gte: query.since ? new Date(query.since) : undefined,
          lte: query.until ? new Date(query.until) : undefined,
        },
      },
      orderBy: { createdAt: "desc" },
      take: Math.min(query.limit ?? 50, 200),
      skip: query.offset ?? 0,
      select: { callSid: true, createdAt: true },
    });
  }

  /** Low-detail audit list endpoint. Never returns signalling content. */
  async listForAudit(query: CdrQuery): Promise<unknown[]> {
    return prisma.cdr.findMany({
      where: {
        fromNumber: query.from,
        toNumber: query.to,
        gatewayType: query.gatewayType,
        status: query.status,
        createdAt: {
          gte: query.since ? new Date(query.since) : undefined,
          lte: query.until ? new Date(query.until) : undefined,
        },
      },
      orderBy: { createdAt: "desc" },
      take: Math.min(query.limit ?? 50, 200),
      skip: query.offset ?? 0,
    });
  }

  async findByCallSid(callSid: string): Promise<unknown> {
    return prisma.cdr.findUnique({ where: { callSid } });
  }

  /** Latest live status for a call, kept in Redis by the event consumer. */
  async getLiveStatus(callSid: string): Promise<unknown> {
    const raw = await redis.get(statusKey(callSid));
    if (!raw) return null;
    try {
      return JSON.parse(raw) as unknown;
    } catch {
      return null;
    }
  }

  async setLiveStatus(callSid: string, status: string, extra: Record<string, unknown>): Promise<void> {
    await redis.set(statusKey(callSid), JSON.stringify({ status, ...extra, updatedAt: new Date().toISOString() }));
  }

  /** Map a normalised gateway event onto the terminal CDR fields (consumer path). */
  toCdrInput(event: CpaasCallEvent): NewCdrInput | null {
    const terminal: CdrStatus[] = ["COMPLETED", "FAILED", "BUSY", "NO_ANSWER", "CANCELED"];
    if (!terminal.includes(event.status)) return null;
    return {
      callSid: event.callSid,
      direction: event.direction,
      from: event.from,
      to: event.to,
      gatewayType: event.gatewayType as GatewayType,
      status: event.status,
      consentFlag: event.consentFlag,
      durationSec: event.durationSec,
      meshHops: event.meshHops,
      bitrate: event.bitrate,
      jitterMs: event.jitterMs,
      packetLossPct: event.packetLossPct,
    };
  }
}

export const cdrService = new CdrService();
