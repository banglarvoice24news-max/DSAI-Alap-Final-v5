import nacl from "tweetnacl";
import { decodeBase64, encodeBase64 } from "tweetnacl-util";
import { createHash } from "node:crypto";

export function deriveX3dhSharedSecret(params: {
  ika: Uint8Array;
  eka: Uint8Array;
  ikb: Uint8Array;
  spkb: Uint8Array;
  opkb?: Uint8Array;
}): string {
  const dh1 = nacl.scalarMult(params.ika, params.spkb);
  const dh2 = nacl.scalarMult(params.eka, params.ikb);
  const dh3 = nacl.scalarMult(params.eka, params.spkb);
  const parts = [dh1, dh2, dh3];
  if (params.opkb) {
    parts.push(nacl.scalarMult(params.eka, params.opkb));
  }
  const concat = Buffer.concat(parts.map((p) => Buffer.from(p)));
  return createHash("sha256").update(concat).digest("base64");
}

export function decodeKey(b64: string): Uint8Array {
  return decodeBase64(b64);
}

export function encodeKey(raw: Uint8Array): string {
  return encodeBase64(raw);
}
