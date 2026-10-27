// FreeSwitchEslClient — inbound ESL (mod_esl) client built on the `modesl`
// package (v1.2.1). Connection lifecycle facts were verified against the
// installed v1.2.1 source: an inbound connection emits `esl::connect`, then
// auto-authenticates with the configured password and emits `esl::ready`;
// `api` callbacks deliver `(event, headers, body)` and the reply text lives in
// the `Reply-Text` header; `bgapi` callbacks deliver the BACKGROUND_JOB event.
//
// All signalling events are translated to normalised CpaasCallEvent records and
// published to the dedicated Redis channel (env.CPAAS_CALL_EVENTS_CHANNEL).
// This channel is NEW — no pre-existing Redis channel is reused or renamed.
//
// INTEGRATION NOTE: FreeSWITCH channel headers and hangup-cause semantics vary
// slightly between builds. The header mapping in `translateEvent` is written
// against the stock FreeSWITCH 1.11 dialplan the project targets; confirm the
// header spellings (`Caller-Caller-ID-Number`, `Caller-Destination-Number`,
// `variable_duration`) against the deployed switch during bring-up.

import { Connection } from "modesl";
import { env } from "../../config/env.js";
import { redis } from "../../lib/redis.js";
import { logger } from "../../lib/logger.js";
import type { CpaasCallEvent, CdrDirection, CdrStatus, CpaasGatewayType } from "./types.js";

const REQUIRED_EVENTS = "CHANNEL_ANSWER CHANNEL_ORIGINATE CHANNEL_BRIDGE CHANNEL_HANGUP_COMPLETE";
const CONNECT_TIMEOUT_MS = 10_000;
const READY_POLL_MS = 50;

export type CpaasEventSink = (event: CpaasCallEvent) => void | Promise<void>;

export interface FreeSwitchEslOptions {
  host?: string;
  port?: number;
  password?: string;
  /** Overrides the default sink for tests and alternative consumers. */
  eventSink?: CpaasEventSink;
  trunk?: string;
  gsmGateway?: string;
  dialplanContext?: string;
}

interface ResolvedEslOptions {
  host: string;
  port: number;
  password: string;
  trunk: string;
  gsmGateway: string;
  dialplanContext: string;
}

interface ChannelHeaderView {
  getHeader(name: string): string | null;
}

/** Reasonable defaults so the same object can be unit-tested without a switch. */
export function defaultEslOptions(): Pick<
  ResolvedEslOptions,
  "host" | "port" | "trunk" | "gsmGateway" | "dialplanContext"
> {
  return {
    host: env.FS_ESL_HOST,
    port: env.FS_ESL_PORT,
    trunk: env.FS_TRUNK_NAME || "dsaialap",
    gsmGateway: env.FS_GSM_GATEWAY || "gsm-gw",
    dialplanContext: env.FS_DIALPLAN_CONTEXT || "cpaas-gsm",
  };
}

export class EslUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EslUnavailableError";
  }
}

export class FreeSwitchEslClient {
  private readonly opts: ResolvedEslOptions;
  private readonly sink: CpaasEventSink;
  private connection: Connection | null = null;
  private ready = false;
  private stopped = false;
  private started = false;
  private readonly knownGatewayByCallSid = new Map<string, CpaasGatewayType>();

  constructor(options: FreeSwitchEslOptions = {}) {
    const defaults = defaultEslOptions();
    this.opts = {
      host: options.host ?? defaults.host,
      port: options.port ?? defaults.port,
      password: options.password ?? env.FS_ESL_PASSWORD,
      trunk: options.trunk ?? defaults.trunk,
      gsmGateway: options.gsmGateway ?? defaults.gsmGateway,
      dialplanContext: options.dialplanContext ?? defaults.dialplanContext,
    };
    this.sink =
      options.eventSink ??
      ((event: CpaasCallEvent) => {
        void redis.publish(env.CPAAS_CALL_EVENTS_CHANNEL, JSON.stringify(event)).catch((err) => {
          logger.error({ err, event: event.type }, "cpaas call event publish failed");
        });
      });
  }

  static isConfigured(): boolean {
    return env.FS_ESL_PASSWORD.length > 0;
  }

  get isReady(): boolean {
    return this.ready;
  }

  /** Begin the connection loop with exponential backoff. Never throws. Idempotent. */
  start(): void {
    if (!this.opts.password) {
      logger.warn("FreeSwitch ESL client not started: FS_ESL_PASSWORD is empty");
      return;
    }
    if (this.started) return;
    this.started = true;
    this.stopped = false;
    void this.connectLoop();
  }

  async stop(): Promise<void> {
    this.stopped = true;
    this.ready = false;
    const conn = this.connection;
    this.connection = null;
    if (conn && typeof conn.disconnect === "function") {
      try {
        conn.disconnect();
      } catch (err) {
        logger.debug({ err }, "esl disconnect error");
      }
    }
  }

  /** Resolves once the switch is ready (used by tests and startup probes). */
  async waitUntilReady(timeoutMs = 5_000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!this.ready) {
      if (Date.now() > deadline) throw new EslUnavailableError("timed out waiting for FreeSWITCH ESL");
      await sleep(READY_POLL_MS);
    }
  }

  /**
   * Fire an outbound originate for a fresh leg and return once FreeSWITCH has
   * accepted the job (bgapi +OK). Leg lifecycle then arrives as channel events
   * on the shared `call:events:cpaas` channel.
   */
  async makeOutboundCall(input: {
    callSid: string;
    to: string;
    from?: string;
    gatewayType: CpaasGatewayType;
    lowBitrate?: boolean;
    timeoutSec?: number;
  }): Promise<string> {
    const vars = [`origination_uuid=${input.callSid}`];
    if (input.from) vars.push(`origination_caller_id_number=${input.from}`);
    if (input.timeoutSec) vars.push(`call_timeout=${input.timeoutSec}`);
    if (input.lowBitrate) {
      // Low-bitrate shaping applies to the FreeSWITCH leg only (opus_bitrate
      // 20000 + SILK). The jambonz leg ignores this flag entirely.
      for (const [name, value] of [
        ["opus_bitrate", "20000"],
        ["absolute_codec_string", "SILK"],
      ] as const) {
        vars.push(`${name}=${value}`);
      }
    }
    const endpoint =
      input.gatewayType === "GSM"
        ? `sofia/gateway/${this.opts.gsmGateway}/${input.to}`
        : `sofia/gateway/${this.opts.trunk}/${input.to}`;
    const dialString = `{${vars.join(",")}}${endpoint}`;
    this.knownGatewayByCallSid.set(input.callSid, input.gatewayType);
    const reply = await this.bgapi("originate", [dialString, "&park()"]);
    if (!reply.startsWith("+OK")) {
      throw new Error(`FreeSWITCH originate rejected: ${reply}`);
    }
    return reply;
  }

  async bridgeCall(legA: string, legB: string): Promise<string> {
    return this.api("uuid_bridge", [legA, legB]);
  }

  /**
   * Transfer a live channel out to the GSM gateway dialplan. The destination
   * extension is the target number inside `cpaas-gsm` context, which the sample
   * dialplan bridges out via the GSM trunk — see the module docs for the exact
   * dialplan contract.
   */
  async transferToGSM(channelUuid: string, destination: string): Promise<string> {
    return this.api("uuid_transfer", [channelUuid, "-both", destination, "xml", this.opts.dialplanContext]);
  }

  async hangup(channelUuid: string): Promise<string> {
    return this.api("uuid_kill", [channelUuid]);
  }

  /**
   * Mesh fallback hook: publishes a terminal `call.failed` event so the CDR
   * trail records why the leg fell back, and lets the orchestrator decide the
   * next leg. No call timing/volume shaping is performed here (see §5).
   */
  async handleMeshFallback(callSid: string, reason: string): Promise<void> {
    await this.sink({
      type: "call.failed",
      callSid,
      direction: "OUTBOUND",
      from: "",
      to: "",
      gatewayType: "MESH",
      status: "FAILED",
      occurredAt: new Date().toISOString(),
      meshHops: 0,
    });
    logger.warn({ callSid, reason }, "cpaas mesh fallback event published");
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private async connectLoop(): Promise<void> {
    let backoffMs = 1_000;
    while (!this.stopped) {
      try {
        await this.connectOnce();
        backoffMs = 1_000;
      } catch (err) {
        if (this.stopped) return;
        logger.warn({ err }, "esl connection attempt failed; retrying");
        await sleep(backoffMs);
        backoffMs = Math.min(backoffMs * 2, 30_000);
      }
    }
  }

  private connectOnce(): Promise<void> {
    return new Promise((resolve, reject) => {
      const conn = new Connection(this.opts.host, this.opts.port, this.opts.password);
      const timeout = setTimeout(() => {
        cleanup();
        reject(new EslUnavailableError(`FreeSWITCH ESL connect timed out (${this.opts.host}:${this.opts.port})`));
      }, CONNECT_TIMEOUT_MS);

      const onReady = (): void => {
        cleanup();
        this.connection = conn;
        this.ready = true;
        this.wireEventHandlers(conn);
        logger.info(
          { host: this.opts.host, port: this.opts.port },
          "FreeSWITCH ESL connected (mod_esl inbound)",
        );
        resolve();
      };
      const onError = (err: Error): void => {
        cleanup();
        if (conn) {
          try {
            conn.disconnect();
          } catch {
            /* ignore */
          }
        }
        reject(err);
      };
      const cleanup = (): void => {
        clearTimeout(timeout);
        conn.removeListener("esl::ready", onReady);
        conn.removeListener("error", onError);
      };

      conn.once("esl::ready", onReady);
      conn.once("error", onError);
    });
  }

  private wireEventHandlers(conn: Connection): void {
    conn.events("json", REQUIRED_EVENTS, () => undefined);
    conn.on("error", (err) => logger.error({ err }, "esl connection error"));
    conn.on("esl::end", () => {
      logger.warn("esl connection closed by switch");
      this.ready = false;
      this.connection = null;
    });
    conn.on("esl::event::**", (...args: unknown[]) => {
      void this.handleRawChannelEvent(args[0] as ChannelHeaderView);
    });
  }

  private async handleRawChannelEvent(raw: unknown): Promise<void> {
    if (!raw || typeof (raw as ChannelHeaderView).getHeader !== "function") return;
    const headerView = raw as ChannelHeaderView;
    const eventName = headerView.getHeader("Event-Name");
    const event = this.translateEvent(eventName, headerView);
    if (event) {
      try {
        await this.sink(event);
        if (["COMPLETED", "FAILED", "BUSY", "NO_ANSWER", "CANCELED"].includes(event.status)) {
          this.knownGatewayByCallSid.delete(event.callSid);
        }
      } catch (err) {
        logger.error({ err, callSid: event.callSid }, "cpaas call event sink failed");
      }
    }
  }

  /** Translate a FreeSWITCH channel event into a normalised CpaasCallEvent. */
  private translateEvent(eventName: string | null, headerView: ChannelHeaderView): CpaasCallEvent | null {
    if (!eventName || !["CHANNEL_ANSWER", "CHANNEL_ORIGINATE", "CHANNEL_HANGUP_COMPLETE"].includes(eventName)) {
      return null;
    }
    const callSid =
      headerView.getHeader("Unique-ID") ??
      headerView.getHeader("Channel-Call-UUID") ??
      headerView.getHeader("Caller-Unique-ID");
    if (!callSid) return null;

    const direction: CdrDirection =
      headerView.getHeader("Call-Direction") === "inbound" ? "INBOUND" : "OUTBOUND";
    const to =
      headerView.getHeader("Caller-Destination-Number") ??
      headerView.getHeader("Destination-Number") ??
      headerView.getHeader("Caller-Channel-Name") ??
      "";
    const from = headerView.getHeader("Caller-Caller-ID-Number") ?? "";
    const durationRaw = headerView.getHeader("variable_duration") ?? headerView.getHeader("duration");
    const durationSec = durationRaw ? parseInt(durationRaw, 10) || undefined : undefined;
    const gatewayType = this.knownGatewayByCallSid.get(callSid) ?? "VOIP";

    if (eventName === "CHANNEL_ANSWER") {
      return {
        type: "call.answered",
        callSid,
        direction,
        from,
        to,
        gatewayType,
        status: "IN_PROGRESS",
        durationSec,
        occurredAt: new Date().toISOString(),
      };
    }

    const hangupCause = headerView.getHeader("Hangup-Cause") ?? "";
    const status = mapHangupCauseToStatus(hangupCause);
    const mappedType =
      status === "NO_ANSWER" ? "call.no_answer" : status === "BUSY" ? "call.busy" : status === "COMPLETED" ? "call.ended" : "call.failed";
    return {
      type: mappedType,
      callSid,
      direction,
      from,
      to,
      gatewayType,
      status,
      durationSec,
      occurredAt: new Date().toISOString(),
    };
  }

  private async api(command: string, args: string[] = []): Promise<string> {
    const conn = await this.requireConnection();
    return new Promise((resolve, reject) => {
      conn.api(command, args, (event) => {
        const reply = event?.getHeader("Reply-Text") ?? "";
        if (reply.startsWith("-ERR")) reject(new Error(reply));
        else resolve(reply);
      });
    });
  }

  private async bgapi(command: string, args: string[] = []): Promise<string> {
    const conn = await this.requireConnection();
    return new Promise((resolve, reject) => {
      conn.bgapi(command, args, (event) => {
        const reply = event?.getHeader("Reply-Text") ?? "";
        if (reply.startsWith("-ERR")) reject(new Error(reply));
        else resolve(reply);
      });
    });
  }

  private async requireConnection(): Promise<Connection> {
    const deadline = Date.now() + 15_000;
    while (!this.connection || !this.ready) {
      if (Date.now() > deadline) throw new EslUnavailableError("FreeSWITCH ESL is not connected");
      await sleep(READY_POLL_MS);
    }
    return this.connection;
  }
}

function mapHangupCauseToStatus(cause: string): CdrStatus {
  switch (cause.toUpperCase()) {
    case "NORMAL_CLEARING":
    case "NORMAL_UNSPECIFIED":
      return "COMPLETED";
    case "NO_ANSWER":
    case "NO_ANSWER_TIMEOUT":
    case "ALLOTTED_TIMEOUT":
      return "NO_ANSWER";
    case "USER_BUSY":
    case "RECOVERY_ON_TIMER_EXPIRE":
      return "BUSY";
    case "ORIGINATOR_CANCEL":
    case "CALL_REJECTED":
      return "CANCELED";
    default:
      return "FAILED";
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Process-wide ESL client shared by the router, the orchestrator and startup. */
export const eslClient = new FreeSwitchEslClient();
