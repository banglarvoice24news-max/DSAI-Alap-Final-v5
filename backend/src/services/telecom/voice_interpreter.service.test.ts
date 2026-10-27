import {
  AlapVoiceResponse,
  type AlapVerb,
} from "./voice_interpreter.service.js";

describe("AlapVoiceResponse (voice interpreter)", () => {
  test("toJSON emits the canonical version:1 script", () => {
    const response = new AlapVoiceResponse()
      .say("Hello", { language: "en" })
      .gather({ numDigits: 1, prompts: [{ text: "Press 1", language: "en" }] })
      .hangup("completed");

    expect(response.toJSON()).toEqual({
      version: 1,
      lowBitrate: false,
      verbs: [
        { verb: "say", text: "Hello", language: "en" },
        {
          verb: "gather",
          numDigits: 1,
          prompts: [{ text: "Press 1", language: "en" }],
        },
        { verb: "hangup", reason: "completed" },
      ],
    });
  });

  test("builder is chainable and the returned JSON cannot be mutated through", () => {
    const response = new AlapVoiceResponse().say("A").say("B");
    expect(response.verbs).toHaveLength(2);

    const copy = response.toJSON() as { verbs: AlapVerb[] };
    copy.verbs.push({ verb: "hangup" });
    expect(response.verbs).toHaveLength(2);
  });

  test("executeSteps runs verbs strictly top-to-bottom and stops on throw", async () => {
    const response = new AlapVoiceResponse().say("one").say("two").hangup();
    const seen: string[] = [];

    await response.executeSteps((verb) => {
      seen.push(verb.verb);
    });

    expect(seen).toEqual(["say", "say", "hangup"]);

    const boom = new AlapVoiceResponse().say("one").say("two");
    const order: string[] = [];
    await expect(
      boom.executeSteps(async (verb, index) => {
        order.push(`${verb.verb}:${index}`);
        if (index === 0) throw new Error("stop");
      }),
    ).rejects.toThrow("stop");
    expect(order).toEqual(["say:0"]);
  });

  test("lowBitrate flag is exposed and toggles the FreeSWITCH-leg channel vars", () => {
    expect(new AlapVoiceResponse().lowBitrate).toBe(false);
    expect(new AlapVoiceResponse({ lowBitrate: true }).toJSON().lowBitrate).toBe(true);

    expect(AlapVoiceResponse.fsCodecChannelVars(false)).toEqual([]);
    expect(AlapVoiceResponse.fsCodecChannelVars(true)).toEqual([
      ["opus_bitrate", "20000"],
      ["absolute_codec_string", "SILK"],
    ]);
  });

  test("toXml escapes special characters in prompt text", () => {
    const xml = new AlapVoiceResponse().say('Tom & "Jerry" <now>').toXml();
    expect(xml).toContain("Tom &amp; &quot;Jerry&quot; &lt;now&gt;");
    expect(xml).toContain("<Response>");
    expect(xml).toContain("</Response>");
  });

  test("fromJSON round-trips a valid script and rejects malformed payloads", () => {
    const original = new AlapVoiceResponse({ lowBitrate: true })
      .say("hello")
      .dial("+8801712345678");
    const rebuilt = AlapVoiceResponse.fromJSON(original.toJSON());
    expect(rebuilt.toJSON()).toEqual(original.toJSON());

    expect(() => AlapVoiceResponse.fromJSON({ version: 2, verbs: [] })).toThrow();
    expect(() => AlapVoiceResponse.fromJSON({ version: 1, lowBitrate: true })).toThrow();
    expect(() => AlapVoiceResponse.fromJSON("nope")).toThrow();
  });
});
