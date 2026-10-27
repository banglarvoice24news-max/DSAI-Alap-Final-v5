// Shared domain types for the isolated telecom / CPaaS subsystem.
// This subsystem lives entirely under src/services/telecom + src/modules/cpaas
// and never imports from the legacy dashboard or the mesh signaling modules,
// keeping the §3.4 isolation contract intact.

/** Physical/logical termination path for a leg. Mirrors the Prisma `GatewayType` enum. */
export type CpaasGatewayType = "MESH" | "VOIP" | "GSM" | "JASMIN" | "JAMBONZ";

/** Direction of a recorded leg relative to this platform. */
export type CdrDirection = "INBOUND" | "OUTBOUND";

/** Lifecycle statuses recorded on CDR rows. Rows are append-only (immutable). */
export type CdrStatus =
  | "QUEUED"
  | "RINGING"
  | "IN_PROGRESS"
  | "COMPLETED"
  | "FAILED"
  | "BUSY"
  | "NO_ANSWER"
  | "CANCELED";

/** Terminal statuses that end a call leg. */
export type CdrTerminalStatus = "COMPLETED" | "FAILED" | "BUSY" | "NO_ANSWER" | "CANCELED";

export interface OutboundCallRequest {
  /** E.164 destination, e.g. +8801XXXXXXX. */
  to: string;
  /** Origination number / platform CLID. */
  from: string;
  /** Preferred gateway. The final choice is ALWAYS re-decided by the §5 policy service. */
  gatewayType?: CpaasGatewayType;
  /**
   * FreeSWITCH-leg only: forces opus_bitrate=20000 and SILK mode on the FS leg.
   * This is a NO-OP on the jambonz leg; see voice_interpreter.service.ts for the
   * documented divergence.
   */
  lowBitrate?: boolean;
  maxDurationSec?: number;
  timeoutSec?: number;
  /** Caller-supplied correlation id, echoed on the CDR. */
  clientRef?: string;
  meshHops?: number;
  /** Explicit §5 consent recorded verbatim on the CDR row. The detection system never reads it. */
  consentFlag?: boolean;
}

export interface OutboundCallResult {
  callSid: string;
  status: CdrStatus;
  gatewayType: CpaasGatewayType;
  sipCode?: number;
}

export interface CallStatusResult {
  callSid: string;
  status: CdrStatus;
  gatewayType?: CpaasGatewayType;
  durationSec?: number;
  meshHops?: number;
  answeredAt?: string;
  terminatedAt?: string;
}

/** Normalised call event flowing from a gateway onto the dedicated pubsub channel. */
export interface CpaasCallEvent {
  type: "call.started" | "call.answered" | "call.ended" | "call.failed" | "call.no_answer" | "call.busy";
  callSid: string;
  direction: CdrDirection;
  from: string;
  to: string;
  gatewayType: CpaasGatewayType;
  status: CdrStatus;
  sipCode?: number;
  durationSec?: number;
  meshHops?: number;
  bitrate?: number;
  jitterMs?: number;
  packetLossPct?: number;
  consentFlag?: boolean;
  occurredAt: string;
}

/**
 * Telephony provider abstraction. The voice interpreter, call-flow logic and the
 * CPaaS router only ever talk to this interface, so a provider (jambonz 0.x
 * self-hosted, FreeSWITCH outbound ESL, or a future licensed IGW/ICX) can be
 * swapped without touching call-flow code.
 */
export interface ITelephonyProvider {
  readonly providerId: CpaasGatewayType;
  createOutboundCall(req: OutboundCallRequest): Promise<OutboundCallResult>;
  getCallStatus(callSid: string): Promise<CallStatusResult>;
  endCall(callSid: string): Promise<void>;
  /**
   * Validates an inbound webhook (signature / shared secret) before the payload is
   * handed to the voice interpreter. Returns true when the caller is trusted.
   */
  validateWebhook(headers: Record<string, string | undefined>, rawBody: string): boolean;
}
