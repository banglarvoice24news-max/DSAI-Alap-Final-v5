// §5 GSM TERMINATION POLICY — the enforcement gate for the zero-cost GSM path.
//
// BTRC COMPLIANCE COMMENT (apply at every point the GSM path is touched):
// In Bangladesh, routing traffic over personal SIMs outside a licensed
// gateway is illegal SIM-box behaviour. The zero-cost GSM path is therefore
// restricted to GENUINELY PERSONAL, ON-NET use by the device's OWN owner:
//   * the originator MUST be the registered SIM owner (never a third party);
//   * explicit consent MUST be present (see consent.service.ts);
//   * the destination MUST be a Bangladeshi number — no international
//     termination over the GSM path, ever; international traffic is routed
//     through a licensed IGW/ICX (jambonz/Jasmin) or blocked.
// Any commercial / B2B international-terminating traffic must go through a
// licensed IGW/ICX. This code does not shape call timing or volume to evade
// BTRC pattern detection; rate caps are load/regulatory limits only.

import { AppError } from "../../lib/http.js";
import { consentService, type SimRegistration } from "./consent.service.js";
import { isBangladeshMobile, normalizeE164 } from "./numbers.js";
import type { CpaasGatewayType } from "./types.js";

/** Licensed gateway a caller will fall back to when the GSM path is refused. */
export type LicensedFallback = "JAMBONZ" | "JASMIN";

export type TerminationDecision =
  | { gateway: "GSM"; mode: "OWNER_PERSONAL"; sim: SimRegistration }
  | { gateway: LicensedFallback; mode: "LICENSED" | "GSM_DENIED_FALLBACK"; reason: string }
  | { gateway: "BLOCKED"; reason: string };

export interface GsmRouteRequest {
  /** E.164 or national number claiming to be the originator. */
  from: string;
  /** Destination number. */
  to: string;
  /**
   * Preferred gateway supplied by the caller. Only `GSM` forces an evaluation
   * of the personal-use path; any other value routes straight to a licensed
   * gateway.
   */
  requestedGateway?: CpaasGatewayType;
  /** Concrete licensed provider the caller will use when GSM is refused. */
  licensedFallback: LicensedFallback;
}

export class GsmPolicyService {
  /**
   * Decide how `from -> to` may terminate. This is the ONLY place that turns a
   * request into a GSM-vs-licensed choice; callers must not bypass it.
   */
  async decideTermination(req: GsmRouteRequest): Promise<TerminationDecision> {
    const from = normalizeE164(req.from);
    const to = normalizeE164(req.to);
    if (!from || !to) {
      throw new AppError(400, "from and to must be valid phone numbers", "CPAAS_INVALID_NUMBER");
    }

    if (req.requestedGateway && req.requestedGateway !== "GSM") {
      const licensed: LicensedFallback =
        req.requestedGateway === "JAMBONZ" || req.requestedGateway === "JASMIN"
          ? req.requestedGateway
          : req.licensedFallback;
      return { gateway: licensed, mode: "LICENSED", reason: `requested gateway ${req.requestedGateway}` };
    }

    const fallback = req.licensedFallback;
    const sim = await consentService.peek(from);
    if (!sim) {
      return this.refuseGsm("no SIM registration for the originator; licensed route required", fallback);
    }
    if (!sim.consentFlag) {
      return this.refuseGsm("consent withdrawn; licensed route required", fallback);
    }
    if (sim.ownerNumber !== from) {
      return this.refuseGsm("originator is not the SIM owner; licensed route required", fallback);
    }
    if (!isBangladeshMobile(to)) {
      return this.refuseGsm("international termination is not allowed over the GSM path", fallback);
    }
    if (to === from) {
      return this.refuseGsm("GSM legs must terminate to another number", fallback);
    }

    // §5 BTRC comment: allowed only because this is the SIM owner terminating to
    // a Bangladeshi number, at personal scale, under explicit consent.
    return { gateway: "GSM", mode: "OWNER_PERSONAL", sim };
  }

  /**
   * Hard gate for flows that cannot tolerate a licensed fallback. Returns the
   * active registration or throws — callers should use decideTermination unless
   * the flow MUST be GSM or fail.
   */
  async requireOwnerPersonalGsm(from: string, to: string): Promise<SimRegistration> {
    const decision = await this.decideTermination({
      from,
      to,
      requestedGateway: "GSM",
      licensedFallback: "JAMBONZ",
    });
    if (decision.gateway !== "GSM") {
      throw new AppError(
        403,
        `GSM path refused: ${decision.reason}`,
        decision.gateway === "BLOCKED" ? "CPAAS_GSM_BLOCKED" : "CPAAS_GSM_LICENSED_REQUIRED",
      );
    }
    return decision.sim;
  }

  private refuseGsm(reason: string, fallback: LicensedFallback): TerminationDecision {
    return { gateway: fallback, mode: "GSM_DENIED_FALLBACK", reason };
  }
}

export const gsmPolicyService = new GsmPolicyService();
