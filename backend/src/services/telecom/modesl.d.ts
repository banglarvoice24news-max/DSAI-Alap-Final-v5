// Precise ambient typings for the `modesl` npm package (v1.2.1, FreeSWITCH ESL).
//
// NOTE: the published `@types/modesl` declarations are inaccurate relative to the
// runtime (the Connection actually extends `eventemitter2` and the api/bgapi
// callbacks receive `(event, headers, body)`), so we vendor a local declaration
// that matches the verified v1.2.1 source instead of relying on them.
declare module "modesl" {
  import { EventEmitter } from "node:events";

  export class Event {
    headers: Array<{ name: string; value: string }>;
    getHeader(name: string): string | null;
    getBody(): string;
    getType(): string;
  }

  /** `api` callbacks resolve with the API response event plus raw headers/body. */
  export type ApiCallback = (event: Event, headers: unknown, body: string) => void;
  /** `bgapi` callbacks resolve with the matching BACKGROUND_JOB event. */
  export type BgapiCallback = (event: Event) => void;

  export class Connection extends EventEmitter {
    constructor(host: string, port: number, password: string);
    connected(): boolean;
    /** Issue a blocking `api <command> <args>` command. */
    api(command: string, args?: string[] | string, cb?: ApiCallback): void;
    /** Issue a non-blocking `bgapi <command> <args>` command correlated by Job-UUID. */
    bgapi(command: string, args?: string[] | string, cb?: BgapiCallback): void;
    bgapi(command: string, args: string[] | string, jobid: string, cb: BgapiCallback): void;
    /** Subscribe to FreeSWITCH events in the given serialisation format. */
    events(type: "json" | "plain" | "xml", events: string, cb?: () => void): void;
    subscribe(events: string, cb?: () => void): void;
    disconnect(): void;
    send(command: string, args?: unknown): void;
    // EventEmitter2-style events actually emitted at runtime:
    on(event: "esl::ready", listener: () => void): this;
    on(event: "esl::connect", listener: () => void): this;
    on(event: "esl::end", listener: () => void): this;
    on(event: "error", listener: (err: Error) => void): this;
    on(event: string, listener: (...args: unknown[]) => void): this;
  }
}
