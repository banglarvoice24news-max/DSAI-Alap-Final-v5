import { createHash, randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import nacl from "tweetnacl";
import { encodeBase64, decodeBase64 } from "tweetnacl-util";

export function generateOtp(length: number): string {
  const max = 10 ** length;
  const limit = Math.floor(0x100000000 / max) * max;
  let n = randomBytes(4).readUInt32BE(0);
  while (n >= limit) {
    n = randomBytes(4).readUInt32BE(0);
  }
  return (n % max).toString().padStart(length, "0");
}

export function hashOtp(otp: string, pepper: string): string {
  return createHash("sha256").update(`${pepper}:${otp}`).digest("hex");
}

export function generateDeviceId(): string {
  return randomBytes(16).toString("hex");
}

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function hashBackupKey(plain: string, salt: string, pepper: string): string {
  const derived = scryptSync(`${pepper}:${plain}`, salt, 64);
  return derived.toString("hex");
}

export function generateBackupSalt(): string {
  return randomBytes(16).toString("hex");
}

export function safeEqualHex(a: string, b: string): boolean {
  const ba = Buffer.from(a, "hex");
  const bb = Buffer.from(b, "hex");
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}

export function generateX25519KeyPair(): { publicKey: string; secretKey: string } {
  const kp = nacl.box.keyPair();
  return {
    publicKey: encodeBase64(kp.publicKey),
    secretKey: encodeBase64(kp.secretKey),
  };
}

export function ecdhSharedSecret(ourSecretB64: string, theirPublicB64: string): string {
  const shared = nacl.box.before(decodeBase64(theirPublicB64), decodeBase64(ourSecretB64));
  return encodeBase64(shared);
}

export function sha256Hex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}
