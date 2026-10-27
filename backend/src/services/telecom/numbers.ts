// E.164 normalisation helpers shared by the telecom services. Kept dependency
// free and deliberately small so they are trivially unit-testable.

import { createHash } from "node:crypto";

function stripFormatting(value: string): string {
  return value.replace(/[\s\-().]/g, "");
}

/**
 * Normalise a Bangladeshi number to a +880-prefixed E.164 string.
 * Accepts "+8801XXXXXXXXX", "8801XXXXXXXXX", "01XXXXXXXXX" (national) and
 * bare "1XXXXXXXXX". Numbers already in a non-BD international format pass
 * through untouched; returns null when the value cannot be interpreted.
 */
export function normalizeE164(value: string): string | null {
  const cleaned = stripFormatting(value.trim());
  if (!/^[+]?\d{7,15}$/.test(cleaned)) return null;

  if (cleaned.startsWith("+8801")) return cleaned;
  if (cleaned.startsWith("8801")) return `+${cleaned}`;
  if (cleaned.startsWith("01") && cleaned.length === 11) return `+880${cleaned.slice(1)}`;
  if (/^1[0-9]{9}$/.test(cleaned)) return `+880${cleaned}`;
  if (cleaned.startsWith("+")) return cleaned;
  if (cleaned.startsWith("880") && cleaned.length >= 11) return `+${cleaned}`;
  return null;
}

/** True when the number is a Bangladeshi mobile (E.164 +8801…). */
export function isBangladeshMobile(value: string): boolean {
  const normalized = normalizeE164(value);
  return normalized !== null && normalized.startsWith("+8801");
}

/** True when the raw value is plausibly a Bangladeshi number. */
export function isBangladeshNumber(value: string): boolean {
  const cleaned = stripFormatting(value.trim());
  return cleaned.startsWith("+880") || cleaned.startsWith("880") || cleaned.startsWith("01");
}

/** Stable, non-reversible handle for a phone number used in Redis keys. */
export function numberHandle(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 32);
}
