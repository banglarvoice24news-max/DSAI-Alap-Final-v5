import { env } from "../../config/env.js";
import { redis } from "../../lib/redis.js";
import { generateOtp, hashOtp, safeEqualHex } from "../../lib/crypto.js";
import { AppError } from "../../lib/http.js";
import { createSmsGateway, type SmsGateway } from "../sms/sms.gateway.js";

const ATTEMPT_PREFIX = "otp_attempts:";
const VERIFY_PREFIX = "otp_verify:";

export class OtpService {
  constructor(private readonly sms: SmsGateway = createSmsGateway()) {}

  private otpKey(phone: string): string {
    return `${env.REDIS_OTP_PREFIX}${phone}`;
  }

  private attemptKey(phone: string): string {
    return `${ATTEMPT_PREFIX}${phone}`;
  }

  async requestOtp(phoneNumber: string): Promise<{ expiresIn: number; debugOtp?: string }> {
    const attempts = await redis.incr(this.attemptKey(phoneNumber));
    if (attempts === 1) {
      await redis.expire(this.attemptKey(phoneNumber), env.OTP_WINDOW_SECONDS);
    }
    if (attempts > env.OTP_MAX_ATTEMPTS) {
      const ttl = await redis.ttl(this.attemptKey(phoneNumber));
      throw new AppError(
        429,
        `Too many OTP requests. Retry after ${Math.max(ttl, 1)} seconds.`,
        "OTP_RATE_LIMITED",
      );
    }

    const otp = generateOtp(env.OTP_LENGTH);
    const payload = JSON.stringify({
      hash: hashOtp(otp, env.BACKUP_KEY_PEPPER),
      createdAt: Date.now(),
    });
    await redis.set(this.otpKey(phoneNumber), payload, "EX", env.REDIS_OTP_TTL_SECONDS);

    const body = `Nexus verification code: ${otp}. Expires in 3 minutes. Do not share this code.`;
    await this.sms.send(phoneNumber, body);

    return {
      expiresIn: env.REDIS_OTP_TTL_SECONDS,
      debugOtp: env.OTP_DEV_ECHO && env.NODE_ENV !== "production" ? otp : undefined,
    };
  }

  async verifyOtp(phoneNumber: string, otp: string): Promise<void> {
    const verifyKey = `${VERIFY_PREFIX}${phoneNumber}`;
    const verifyAttempts = await redis.incr(verifyKey);
    if (verifyAttempts === 1) {
      await redis.expire(verifyKey, env.REDIS_OTP_TTL_SECONDS);
    }
    if (verifyAttempts > env.OTP_MAX_ATTEMPTS) {
      await redis.del(this.otpKey(phoneNumber));
      throw new AppError(429, "Too many OTP verification attempts", "OTP_VERIFY_RATE_LIMITED");
    }

    const raw = await redis.get(this.otpKey(phoneNumber));
    if (!raw) {
      throw new AppError(400, "OTP expired or not found", "OTP_EXPIRED");
    }
    const stored = JSON.parse(raw) as { hash: string };
    const incoming = hashOtp(otp, env.BACKUP_KEY_PEPPER);
    if (!safeEqualHex(incoming, stored.hash)) {
      throw new AppError(400, "Invalid OTP", "OTP_INVALID");
    }
    await redis.del(this.otpKey(phoneNumber), verifyKey);
  }
}

export const otpService = new OtpService();
