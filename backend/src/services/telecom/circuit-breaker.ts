import { logger } from "../../lib/logger.js";

export interface CircuitBreakerOptions {
  /** Short identifier used in logs, e.g. "jambonz" or "android-gsm". */
  name: string;
  /** Consecutive failures that trip the breaker open (default 5). */
  failureThreshold?: number;
  /** Time the breaker stays open before probing with a half-open call (default 30s). */
  resetTimeoutMs?: number;
}

export type BreakerState = "closed" | "open" | "half-open";

export class CircuitOpenError extends Error {
  constructor(public readonly breakerName: string) {
    super(`Circuit breaker "${breakerName}" is open`);
    this.name = "CircuitOpenError";
  }
}

/**
 * Minimal fault-isolating circuit breaker used around every external gateway
 * call (jambonz, Jasmin, the Android GSM relay). It prevents a wedged gateway
 * from cascading retries through the whole CPaaS layer.
 */
export class CircuitBreaker {
  private readonly name: string;
  private readonly failureThreshold: number;
  private readonly resetTimeoutMs: number;
  private state: BreakerState = "closed";
  private consecutiveFailures = 0;
  private openedAt = 0;

  constructor(options: CircuitBreakerOptions) {
    this.name = options.name;
    this.failureThreshold = options.failureThreshold ?? 5;
    this.resetTimeoutMs = options.resetTimeoutMs ?? 30_000;
  }

  getState(): BreakerState {
    if (this.state === "open" && Date.now() - this.openedAt >= this.resetTimeoutMs) {
      // Transition to half-open lazily so the next call probes the gateway.
      this.state = "half-open";
    }
    return this.state;
  }

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.getState() === "open") {
      throw new CircuitOpenError(this.name);
    }
    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (err) {
      this.onFailure(err);
      throw err;
    }
  }

  private onSuccess(): void {
    if (this.state === "half-open") {
      logger.info({ breaker: this.name }, "circuit breaker recovered");
    }
    this.state = "closed";
    this.consecutiveFailures = 0;
    this.openedAt = 0;
  }

  private onFailure(err: unknown): void {
    this.consecutiveFailures += 1;
    if (this.state === "half-open" || this.consecutiveFailures >= this.failureThreshold) {
      this.state = "open";
      this.openedAt = Date.now();
      logger.warn(
        { breaker: this.name, consecutiveFailures: this.consecutiveFailures },
        "circuit breaker opened after repeated gateway failures",
      );
    }
    if (err instanceof CircuitOpenError) {
      logger.warn({ breaker: this.name }, "circuit breaker rejected a call while open");
    }
  }

  /** Force the breaker closed (used by health checks or operator intervention). */
  reset(): void {
    this.state = "closed";
    this.consecutiveFailures = 0;
    this.openedAt = 0;
  }
}
