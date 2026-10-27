// §5 CONSENT SERVICE — harm-reduction boundary for the personal GSM path.
//
// Regulatory posture (Bangladesh, 2026): carrying third-party traffic over a
// personal SIM (SIM-box style) is illegal. The ONLY defensible use of the
// zero-cost GSM path is genuinely personal, on-net traffic originated by the
// SIM's own owner. This service therefore enforces:
//   1. single SIM per owner number (a second device cannot be registered while
//      a consenting SIM exists for the same number);
//   2. an explicit, per-owner consent flag that must be true before the GSM
//      path is ever offered;
//   3. an immutable, append-only consent audit trail in Redis (RPUSH only;
//      never updated, never trimmed in code).
// IMPORTANT: the pattern-detection system does NOT read consent flags. Consent
// is a compliance control for the operator, not an input to detection. Nothing
// in this subsystem shapes call timing or volume to evade BTRC pattern
// detection; the per-device caps are load/regulatory limits only.

import { env } from "../../config/env.js";
import { AppError } from "../../lib/http.js";
import { redis } from "../../lib/redis.js";
import { numberHandle } from "./numbers.js";

export interface SimRegistration {
  deviceId: string;
  /** E.164 owner number. GSM legs may only be originated FROM this number. */
  ownerNumber: string;
  consentFlag: boolean;
  consentGrantedAt: string;
  consentExpiresAt: string;
}

export interface ConsentAuditEntry {
  ts: string;
  action: "register" | "revoke" | "renew";
  ownerNumber: string;
  deviceId: string;
}

function simKey(ownerNumber: string): string {
  return `${env.CPAAS_REDIS_PREFIX}sim:${numberHandle(ownerNumber)}`;
}

function auditKey(ownerNumber: string): string {
  return `${env.CPAAS_REDIS_PREFIX}sim:audit:${numberHandle(ownerNumber)}`;
}

function defaultExpiry(): string {
  const ms = env.CPAAS_CONSENT_TTL_DAYS * 24 * 60 * 60 * 1000;
  return new Date(Date.now() + ms).toISOString();
}

export class ConsentService {
  /**
   * Register a GSM gateway device against the owner's number. Enforces the
   * single-SIM-per-user invariant: registration is refused while an active
   * consenting SIM exists for a DIFFERENT deviceId. Re-registering the same
   * device simply renews consent.
   */
  async register(ownerNumber: string, deviceId: string): Promise<SimRegistration> {
    const existingRaw = await redis.get(simKey(ownerNumber));
    if (existingRaw) {
      const existing = JSON.parse(existingRaw) as SimRegistration;
      if (existing.consentFlag && existing.deviceId !== deviceId) {
        throw new AppError(
          409,
          "An active SIM is already registered for this number; revoke it before registering another",
          "CPAAS_SIM_ALREADY_REGISTERED",
        );
      }
    }
    const registration: SimRegistration = {
      deviceId,
      ownerNumber,
      consentFlag: true,
      consentGrantedAt: new Date().toISOString(),
      consentExpiresAt: defaultExpiry(),
    };
    await redis.set(simKey(ownerNumber), JSON.stringify(registration));
    await this.appendAudit(ownerNumber, deviceId, "register");
    return registration;
  }

  /**
   * Explicit consent check. Throws when there is no registration, consent is
   * not flagged, or consent has lapsed. The GSM path must pass this gate.
   */
  async requireConsent(ownerNumber: string): Promise<SimRegistration> {
    const existingRaw = await redis.get(simKey(ownerNumber));
    if (!existingRaw) {
      throw new AppError(403, "No SIM registration for this owner", "CPAAS_SIM_NOT_REGISTERED");
    }
    const registration = JSON.parse(existingRaw) as SimRegistration;
    if (!registration.consentFlag) {
      throw new AppError(403, "Consent for the GSM path has been withdrawn", "CPAAS_CONSENT_WITHDRAWN");
    }
    if (new Date(registration.consentExpiresAt).getTime() <= Date.now()) {
      throw new AppError(403, "Consent for the GSM path has expired", "CPAAS_CONSENT_EXPIRED");
    }
    return registration;
  }

  /** Read current registration without throwing (used by the policy service). */
  async peek(ownerNumber: string): Promise<SimRegistration | null> {
    const raw = await redis.get(simKey(ownerNumber));
    if (!raw) return null;
    try {
      return JSON.parse(raw) as SimRegistration;
    } catch {
      return null;
    }
  }

  /** Withdraw consent (marks the flag false, keeps the immutable audit trail). */
  async revoke(ownerNumber: string): Promise<void> {
    const raw = await redis.get(simKey(ownerNumber));
    if (!raw) {
      throw new AppError(404, "No SIM registration for this owner", "CPAAS_SIM_NOT_REGISTERED");
    }
    const registration = JSON.parse(raw) as SimRegistration;
    registration.consentFlag = false;
    await redis.set(simKey(ownerNumber), JSON.stringify(registration));
    await this.appendAudit(ownerNumber, registration.deviceId, "revoke");
  }

  /** Append-only consent audit trail (never trimmed or updated in code). */
  async listAudit(ownerNumber: string, limit = 100): Promise<ConsentAuditEntry[]> {
    const raw = await redis.lrange(auditKey(ownerNumber), 0, limit - 1);
    return raw
      .map((entry) => {
        try {
          return JSON.parse(entry) as ConsentAuditEntry;
        } catch {
          return null;
        }
      })
      .filter((entry): entry is ConsentAuditEntry => entry !== null);
  }

  private async appendAudit(ownerNumber: string, deviceId: string, action: ConsentAuditEntry["action"]): Promise<void> {
    const entry: ConsentAuditEntry = {
      ts: new Date().toISOString(),
      action,
      ownerNumber,
      deviceId,
    };
    // RPUSH only — entries are immutable. A retention purge (if ever needed)
    // is an operator decision, not something this code performs.
    await redis.rpush(auditKey(ownerNumber), JSON.stringify(entry));
  }
}

export const consentService = new ConsentService();
