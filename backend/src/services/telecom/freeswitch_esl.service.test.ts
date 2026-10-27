// Mocked-integration tests for FreeSwitchEslClient. We mock the `modesl`
// Connection (verified runtime behaviour: emits `esl::ready` after the inbound
// handshake, `api`/`bgapi` callbacks carry the reply in `Reply-Text`) and the
// Redis sink, then drive channel events through the client's normalisation to
// assert the `call:events:cpaas` contract.

import { EventEmitter } from "node:events";
import type { CpaasCallEvent } from "./types.js";

type HeaderBag = Record<string, string>;

class FakeHeaderView {
  constructor(private readonly headers: HeaderBag) {}
  getHeader(name: string): string | null {
    return this.headers[name] ?? null;
  }
}

interface BgapiRecord {
  command: string;
  args: string[];
  cb: (event: { getHeader(name: string): string | null }) => void;
}

class FakeConnection extends EventEmitter {
  eventsCalls: Array<{ type: string; events: string }> = [];
  apiCalls: Array<{ command: string; args: string[] }> = [];
  bgapiCalls: BgapiRecord[] = [];
  disconnected = false;

  constructor(host: string, port: number, password: string) {
    super();
    void host;
    void port;
    void password;
    // Simulate the inbound ESL handshake completing on the next tick.
    setImmediate(() => this.emit("esl::ready"));
  }

  api(command: string, args: string[] = [], cb?: (event: { getHeader(name: string): string | null }) => void): void {
    this.apiCalls.push({ command, args });
    cb?.({ getHeader: (name: string) => (name === "Reply-Text" ? "+OK api done" : null) });
  }

  bgapi(
    command: string,
    args: string[] = [],
    cb?: (event: { getHeader(name: string): string | null }) => void,
  ): void {
    this.bgapiCalls.push({ command, args, cb: cb ?? (() => undefined) });
    cb?.({ getHeader: (name: string) => (name === "Reply-Text" ? "+OK 123" : null) });
  }

  events(type: "json" | "plain" | "xml", events: string): void {
    this.eventsCalls.push({ type, events });
  }

  disconnect(): void {
    this.disconnected = true;
  }

  fireChannelEvent(headers: HeaderBag): void {
    this.emit("esl::event::**", new FakeHeaderView(headers));
  }
}

jest.mock("modesl", () => ({ Connection: FakeConnection }));
jest.mock("../../lib/redis.js", () => ({
  redis: { publish: jest.fn().mockResolvedValue(1) },
}));
jest.mock("../../config/env.js", () => ({
  env: {
    LOG_LEVEL: "silent",
    FS_ESL_HOST: "127.0.0.1",
    FS_ESL_PORT: 8021,
    FS_ESL_PASSWORD: "ClueCon",
    FS_TRUNK_NAME: "dsaialap",
    FS_GSM_GATEWAY: "gsm-gw",
    FS_DIALPLAN_CONTEXT: "cpaas-gsm",
    CPAAS_CALL_EVENTS_CHANNEL: "call:events:cpaas",
    CPAAS_REDIS_PREFIX: "cpaas:",
  },
}));

import { FreeSwitchEslClient } from "./freeswitch_esl.service.js";

describe("FreeSwitchEslClient (mocked integration)", () => {
  test("starts, becomes ready and originates a GSM leg with low-bitrate vars", async () => {
    const sink: CpaasCallEvent[] = [];
    const client = new FreeSwitchEslClient({ eventSink: (e) => void sink.push(e) });
    client.start();
    await client.waitUntilReady(2_000);

    const reply = await client.makeOutboundCall({
      callSid: "uuid-leg-1",
      to: "+8801711111111",
      from: "+8801811111111",
      gatewayType: "GSM",
      lowBitrate: true,
      timeoutSec: 45,
    });

    expect(reply.startsWith("+OK")).toBe(true);

    const conn = (client as unknown as { connection: FakeConnection }).connection;
    expect(conn).toBeInstanceOf(FakeConnection);
    const bgapi = conn.bgapiCalls.find((call) => call.command === "originate");
    expect(bgapi).toBeDefined();
    expect(bgapi?.args[0]).toContain("origination_uuid=uuid-leg-1");
    expect(bgapi?.args[0]).toContain("origination_caller_id_number=+8801811111111");
    expect(bgapi?.args[0]).toContain("opus_bitrate=20000");
    expect(bgapi?.args[0]).toContain("absolute_codec_string=SILK");
    expect(bgapi?.args[0]).toContain("sofia/gateway/gsm-gw/+8801711111111");

    expect(conn.eventsCalls[0]).toMatchObject({ type: "json" });
    await client.stop();
  });

  test("translates CHANNEL_ANSWER and CHANNEL_HANGUP_COMPLETE into normalised events", async () => {
    const sink: CpaasCallEvent[] = [];
    const client = new FreeSwitchEslClient({ eventSink: (e) => void sink.push(e) });
    client.start();
    await client.waitUntilReady(2_000);

    await client.makeOutboundCall({
      callSid: "uuid-leg-2",
      to: "+8801711111112",
      gatewayType: "GSM",
      lowBitrate: false,
    });

    const conn = (client as unknown as { connection: FakeConnection }).connection;
    conn.fireChannelEvent({
      "Event-Name": "CHANNEL_ANSWER",
      "Unique-ID": "uuid-leg-2",
      "Call-Direction": "outbound",
      "Caller-Destination-Number": "+8801711111112",
      "Caller-Caller-ID-Number": "+8801811111111",
    });
    conn.fireChannelEvent({
      "Event-Name": "CHANNEL_HANGUP_COMPLETE",
      "Unique-ID": "uuid-leg-2",
      "Call-Direction": "outbound",
      "Caller-Destination-Number": "+8801711111112",
      "Caller-Caller-ID-Number": "+8801811111111",
      "Hangup-Cause": "NORMAL_CLEARING",
      "variable_duration": "42",
    });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(sink).toHaveLength(2);
    expect(sink[0]).toMatchObject({
      type: "call.answered",
      callSid: "uuid-leg-2",
      status: "IN_PROGRESS",
      gatewayType: "GSM",
    });
    expect(sink[1]).toMatchObject({
      type: "call.ended",
      callSid: "uuid-leg-2",
      status: "COMPLETED",
      gatewayType: "GSM",
      durationSec: 42,
    });
    await client.stop();
  });

  test("maps hangup causes onto the CDR status set (busy, no answer, cancelled)", async () => {
    const sink: CpaasCallEvent[] = [];
    const client = new FreeSwitchEslClient({ eventSink: (e) => void sink.push(e) });
    client.start();
    await client.waitUntilReady(2_000);

    for (const [index, cause] of [
      "USER_BUSY",
      "NO_ANSWER",
      "ORIGINATOR_CANCEL",
      "UNSPECIFIED",
    ].entries()) {
      const callSid = `uuid-${index}`;
      const conn = (client as unknown as { connection: FakeConnection }).connection;
      await client.makeOutboundCall({ callSid, to: "+8801700000000", gatewayType: "VOIP" });
      conn.fireChannelEvent({
        "Event-Name": "CHANNEL_HANGUP_COMPLETE",
        "Unique-ID": callSid,
        "Call-Direction": "outbound",
        "Hangup-Cause": cause,
      });
    }
    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(sink.map((event) => [event.status, event.type])).toEqual([
      ["BUSY", "call.busy"],
      ["NO_ANSWER", "call.no_answer"],
      ["CANCELED", "call.failed"],
      ["FAILED", "call.failed"],
    ]);
    await client.stop();
  });

  test("stop() closes the connection and drops the ready flag", async () => {
    const client = new FreeSwitchEslClient();
    client.start();
    await client.waitUntilReady(2_000);
    const conn = (client as unknown as { connection: FakeConnection }).connection;

    await client.stop();
    expect(conn.disconnected).toBe(true);
    expect((client as unknown as { ready: boolean }).ready).toBe(false);
  });
});
