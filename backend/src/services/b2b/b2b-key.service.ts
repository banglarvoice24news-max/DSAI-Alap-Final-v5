import { createHash, timingSafeEqual } from "node:crypto";
import { env } from "../../config/env.js";
import { AppError } from "../../lib/http.js";

export type B2bTier = "starter" | "pro" | "enterprise";

export interface B2bTenant {
  id: string;
  name: string;
  tier: B2bTier;
  rpm: number;
  webhookUrl?: string;
  keyFingerprint: string;
}

const TIER_RPM: Record<B2bTier, number> = {
  starter: 60,
  pro: 300,
  enterprise: 2000,
};

function fingerprint(rawKey: string): string {
  return createHash("sha256").update(rawKey).digest("hex").slice(0, 16);
}

function parseTenants(): B2bTenant[] {
  const raw = env.DSAIALAP_B2B_KEYS;
  if (!raw) return [];
  return raw
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [key, name, tier, webhookUrl] = entry.split("|").map((s) => s.trim());
      const resolvedTier = (tier as B2bTier) in TIER_RPM ? (tier as B2bTier) : "starter";
      return {
        id: fingerprint(key),
        name: name || `tenant-${fingerprint(key)}`,
        tier: resolvedTier,
        rpm: TIER_RPM[resolvedTier],
        webhookUrl: webhookUrl || undefined,
        keyFingerprint: fingerprint(key),
        _key: key,
      } as B2bTenant & { _key: string };
    });
}

export class B2bKeyService {
  verify(headerValue: string | undefined): B2bTenant {
    if (!headerValue) {
      throw new AppError(401, "Missing x-dsaialap-key", "B2B_KEY_MISSING");
    }
    const tenants = parseTenants() as Array<B2bTenant & { _key: string }>;
    if (tenants.length === 0) {
      throw new AppError(503, "B2B engine is not configured", "B2B_DISABLED");
    }
    const incoming = Buffer.from(headerValue);
    const match = tenants.find((tenant) => {
      const stored = Buffer.from(tenant._key);
      if (stored.length !== incoming.length) return false;
      return timingSafeEqual(stored, incoming);
    });
    if (!match) {
      throw new AppError(401, "Invalid B2B API key", "B2B_KEY_INVALID");
    }
    const { _key: _omit, ...safe } = match;
    return safe;
  }
}

export const b2bKeyService = new B2bKeyService();
