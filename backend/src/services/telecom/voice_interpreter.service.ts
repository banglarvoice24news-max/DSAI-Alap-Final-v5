// AlapVoiceResponse: a JSON-first, TwiML-equivalent voice scripting model.
//
// The interpreter is intentionally provider-agnostic. Verbs are declared in
// JSON and "executed top-to-bottom" by an executor that resolves each verb
// against whichever provider handled the leg. Two serialisations exist:
//   - toJSON()  -> the canonical form consumed by the jambonz BYOC provider.
//   - toXml()   -> a TwiML-compatible document for Eqivo/FreeSWITCH interop.
//
// LOW-BITRATE DIVERGENCE (documented on purpose):
//   When `lowBitrate` is set, the FreeSWITCH leg is built with opus_bitrate=20000
//   plus SILK-mode codec negotiation (see `fsCodecChannelVars`). jambonz ignores
//   codec shaping at the application layer, so on a jambonz leg this flag is a
//   no-op; the two legs therefore legitimately differ and that is by design.

export interface SayPrompt {
  text: string;
  language?: "en" | "bn";
  voice?: string;
  loop?: number;
}

export type AlapVerb =
  | { verb: "say"; text: string; language?: "en" | "bn"; voice?: string; loop?: number }
  | {
      verb: "dial";
      to: string;
      from?: string;
      /** Route hint only; the §5 policy service is the source of truth for the real gateway. */
      gateway?: "VOIP" | "GSM" | "MESH" | "JAMBONZ";
      timeout?: number;
      callerId?: string;
      maxDurationSec?: number;
      lowBitrate?: boolean;
    }
  | {
      verb: "gather";
      numDigits?: number;
      timeoutMs?: number;
      finishOnKey?: string;
      prompts?: SayPrompt[];
    }
  | {
      verb: "record";
      maxDurationSec?: number;
      finishOnKey?: string;
      beep?: boolean;
    }
  | { verb: "redirect"; url: string; method?: "GET" | "POST" }
  | { verb: "hangup"; reason?: string };

export interface AlapVoiceScript {
  version: 1;
  /** FreeSWITCH-leg only: opus_bitrate=20000 + SILK mode. No-op on jambonz legs. */
  lowBitrate: boolean;
  verbs: AlapVerb[];
}

export type VerbHandler = (verb: AlapVerb, index: number, script: AlapVoiceScript) => void | Promise<void>;

function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function sayToXml(say: Extract<AlapVerb, { verb: "say" }>): string {
  const attrs: string[] = [];
  if (say.voice) attrs.push(`voice="${escapeXml(say.voice)}"`);
  if (say.language) attrs.push(`language="${escapeXml(say.language)}"`);
  if (say.loop !== undefined) attrs.push(`loop="${say.loop}"`);
  const attrStr = attrs.length > 0 ? ` ${attrs.join(" ")}` : "";
  return `<Say${attrStr}>${escapeXml(say.text)}</Say>`;
}

function promptToXml(prompt: SayPrompt): string {
  const attrs: string[] = [];
  if (prompt.language) attrs.push(`language="${escapeXml(prompt.language)}"`);
  const attrStr = attrs.length > 0 ? ` ${attrs.join(" ")}` : "";
  return `<Say${attrStr}>${escapeXml(prompt.text)}</Say>`;
}

export class AlapVoiceResponse {
  private readonly _verbs: AlapVerb[] = [];
  private readonly _lowBitrate: boolean;

  constructor(options: { lowBitrate?: boolean } = {}) {
    this._lowBitrate = options.lowBitrate ?? false;
  }

  /** Build an instance from a previously serialised script (webhook resume path). */
  static fromJSON(raw: unknown): AlapVoiceResponse {
    if (!isAlapVoiceScript(raw)) {
      throw new Error("Invalid AlapVoiceResponse script payload");
    }
    const response = new AlapVoiceResponse({ lowBitrate: raw.lowBitrate });
    response._verbs.push(...raw.verbs);
    return response;
  }

  say(text: string, options: Omit<SayPrompt, "text"> = {}): this {
    this._verbs.push({ verb: "say", text, ...options });
    return this;
  }

  dial(to: string, options: Omit<Extract<AlapVerb, { verb: "dial" }>, "verb" | "to"> = {}): this {
    this._verbs.push({ verb: "dial", to, ...options });
    return this;
  }

  gather(options: Omit<Extract<AlapVerb, { verb: "gather" }>, "verb"> = {}): this {
    this._verbs.push({ verb: "gather", ...options });
    return this;
  }

  record(options: Omit<Extract<AlapVerb, { verb: "record" }>, "verb"> = {}): this {
    this._verbs.push({ verb: "record", ...options });
    return this;
  }

  redirect(url: string, method: "GET" | "POST" = "POST"): this {
    this._verbs.push({ verb: "redirect", url, method });
    return this;
  }

  hangup(reason?: string): this {
    this._verbs.push({ verb: "hangup", reason });
    return this;
  }

  get verbs(): readonly AlapVerb[] {
    return this._verbs;
  }

  get lowBitrate(): boolean {
    return this._lowBitrate;
  }

  get empty(): boolean {
    return this._verbs.length === 0;
  }

  toJSON(): AlapVoiceScript {
    // Deep copy so callers cannot mutate the script through the returned object.
    return {
      version: 1,
      lowBitrate: this._lowBitrate,
      verbs: JSON.parse(JSON.stringify(this._verbs)) as AlapVerb[],
    };
  }

  /**
   * Serialise to a TwiML-compatible XML document (for Eqivo). Only an escape
   * hatch for switch-side interop; the canonical format is toJSON().
   */
  toXml(): string {
    const body = this._verbs.map((verb) => this.verbToXml(verb)).join("");
    return `<Response>${body}</Response>`;
  }

  /**
   * Execute verbs strictly top-to-bottom. If the handler throws, execution stops
   * and the error propagates to the caller (the gateway leg then fails closed).
   */
  async executeSteps(handler: VerbHandler): Promise<void> {
    const script = this.toJSON();
    for (let index = 0; index < script.verbs.length; index += 1) {
      await handler(script.verbs[index], index, script);
    }
  }

  /**
   * Channel variables applied to the FreeSWITCH leg ONLY when lowBitrate is set.
   * Values follow the spec (opus_bitrate=20000 + SILK mode). The exact mod_opus /
   * codec variable names should be confirmed against the deployed FreeSWITCH
   * build during integration; they are isolated here so the change is one spot.
   */
  static fsCodecChannelVars(lowBitrate: boolean): Array<[string, string]> {
    if (!lowBitrate) return [];
    return [
      ["opus_bitrate", "20000"],
      ["absolute_codec_string", "SILK"],
    ];
  }

  private verbToXml(verb: AlapVerb): string {
    switch (verb.verb) {
      case "say":
        return sayToXml(verb);
      case "dial": {
        const attrs: string[] = [];
        if (verb.callerId) attrs.push(`callerId="${escapeXml(verb.callerId)}"`);
        if (verb.timeout !== undefined) attrs.push(`timeout="${verb.timeout}"`);
        if (verb.maxDurationSec !== undefined) attrs.push(`timeLimit="${verb.maxDurationSec}"`);
        const attrStr = attrs.length > 0 ? ` ${attrs.join(" ")}` : "";
        return `<Dial${attrStr}><Number>${escapeXml(verb.to)}</Number></Dial>`;
      }
      case "gather": {
        const attrs: string[] = [];
        if (verb.numDigits !== undefined) attrs.push(`numDigits="${verb.numDigits}"`);
        if (verb.timeoutMs !== undefined) attrs.push(`timeout="${Math.round(verb.timeoutMs / 1000)}"`);
        if (verb.finishOnKey !== undefined) attrs.push(`finishOnKey="${escapeXml(verb.finishOnKey)}"`);
        const attrStr = attrs.length > 0 ? ` ${attrs.join(" ")}` : "";
        const prompts = (verb.prompts ?? []).map((prompt) => promptToXml(prompt)).join("");
        return `<Gather${attrStr}>${prompts}</Gather>`;
      }
      case "record": {
        const attrs: string[] = [];
        if (verb.maxDurationSec !== undefined) attrs.push(`maxLength="${verb.maxDurationSec}"`);
        if (verb.finishOnKey !== undefined) attrs.push(`finishOnKey="${escapeXml(verb.finishOnKey)}"`);
        if (verb.beep === true) attrs.push('playBeep="true"');
        const attrStr = attrs.length > 0 ? ` ${attrs.join(" ")}` : "";
        return `<Record${attrStr}/>`;
      }
      case "redirect":
        return `<Redirect method="${verb.method ?? "POST"}">${escapeXml(verb.url)}</Redirect>`;
      case "hangup": {
        const reason = verb.reason ? ` reason="${escapeXml(verb.reason)}"` : "";
        return `<Hangup${reason}/>`;
      }
    }
  }
}

function isAlapVerb(value: unknown): value is AlapVerb {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.verb === "string" &&
    ["say", "dial", "gather", "record", "redirect", "hangup"].includes(candidate.verb)
  );
}

function isAlapVoiceScript(value: unknown): value is AlapVoiceScript {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return (
    candidate.version === 1 &&
    typeof candidate.lowBitrate === "boolean" &&
    Array.isArray(candidate.verbs) &&
    candidate.verbs.every((verb) => isAlapVerb(verb))
  );
}
