import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3001),
  HOST: z.string().default("0.0.0.0"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),

  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  REDIS_OTP_PREFIX: z.string().default("otp:"),
  REDIS_OTP_TTL_SECONDS: z.coerce.number().int().positive().default(180),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(3),
  OTP_WINDOW_SECONDS: z.coerce.number().int().positive().default(900),
  OTP_LENGTH: z.coerce.number().int().min(4).max(8).default(6),
  OTP_DEV_ECHO: z
    .string()
    .optional()
    .transform((v) => v === "true"),

  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRES_IN: z.string().default("15m"),
  JWT_REFRESH_EXPIRES_IN: z.string().default("30d"),
  JWT_ISSUER: z.string().default("nexus-comm"),
  JWT_AUDIENCE: z.string().default("nexus-mobile"),

  COOKIE_DOMAIN: z.string().optional().default(""),
  COOKIE_SECURE: z
    .string()
    .optional()
    .transform((v) => v === "true"),
  COOKIE_SAMESITE: z.enum(["strict", "lax", "none"]).default("strict"),
  REFRESH_COOKIE_NAME: z.string().default("nexus_rt"),

  CORS_ORIGINS: z
    .string()
    .default("http://localhost:5173,https://dsaialap.banglarvoice24news.com")
    .transform((v) => v.split(",").map((s) => s.trim()).filter(Boolean)),

  TWILIO_ACCOUNT_SID: z.string().optional().default(""),
  TWILIO_AUTH_TOKEN: z.string().optional().default(""),
  TWILIO_FROM_NUMBER: z.string().optional().default(""),

  SMS_API_URL: z.string().optional().default(""),
  SMS_API_KEY: z.string().optional().default(""),
  SMS_API_FROM: z.string().optional().default(""),

  FCM_PROJECT_ID: z.string().optional().default(""),
  FCM_CLIENT_EMAIL: z.string().optional().default(""),
  FCM_PRIVATE_KEY: z.string().optional().default(""),
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional().default(""),

  BACKUP_KEY_PEPPER: z.string().min(16),
  BACKUP_CHALLENGE_TTL_SECONDS: z.coerce.number().int().positive().default(120),

  SIGNALING_PING_INTERVAL_MS: z.coerce.number().int().positive().default(25000),
  SIGNALING_MAX_BUFFER_SIZE: z.coerce.number().int().positive().default(1_048_576),

  DSAIALAP_B2B_KEYS: z.string().optional().default(""),
  DSAIALAP_PUBLIC_HOST: z.string().optional().default("dsaialap.banglarvoice24news.com"),

  // --- CPaaS / telecom layer (all optional; off by default, see §3.2) ---
  ENABLE_CPAAS_LAYER: z
    .string()
    .optional()
    .default("false")
    .transform((v) => v === "true"),
  CPAAS_REDIS_PREFIX: z.string().default("cpaas:"),
  CPAAS_CALL_EVENTS_CHANNEL: z.string().default("call:events:cpaas"),
  CPAAS_CONSENT_TTL_DAYS: z.coerce.number().int().positive().default(30),
  CPAAS_API_KEY_MAX_RPM: z.coerce.number().int().positive().default(120),
  CPAAS_SMS_GSM_MAX_RPM: z.coerce.number().int().positive().default(2),
  CPAAS_SMS_GSM_DAILY_CAP: z.coerce.number().int().positive().default(30),

  FS_ESL_HOST: z.string().default("127.0.0.1"),
  FS_ESL_PORT: z.coerce.number().int().positive().default(8021),
  FS_ESL_PASSWORD: z.string().optional().default(""),
  FS_TRUNK_NAME: z.string().optional().default(""),
  FS_GSM_GATEWAY: z.string().optional().default(""),
  FS_DIALPLAN_CONTEXT: z.string().optional().default(""),

  JAMBONZ_API_BASE_URL: z.string().optional().default(""),
  JAMBONZ_ACCOUNT_SID: z.string().optional().default(""),
  JAMBONZ_API_TOKEN: z.string().optional().default(""),
  JAMBONZ_CARRIER: z.string().optional().default(""),
  JAMBONZ_CALLBACK_BASE_URL: z.string().optional().default(""),
  JAMBONZ_WEBHOOK_USERNAME: z.string().optional().default(""),
  JAMBONZ_WEBHOOK_PASSWORD: z.string().optional().default(""),
  JAMBONZ_WEBHOOK_SECRET: z.string().optional().default(""),

  JASMIN_HTTP_URL: z.string().optional().default(""),
  JASMIN_HTTP_USERNAME: z.string().optional().default(""),
  JASMIN_HTTP_PASSWORD: z.string().optional().default(""),

  ANDROID_GSM_BASE_URL: z.string().optional().default(""),
  ANDROID_GSM_TOKEN: z.string().optional().default(""),
  ANDROID_GSM_DEVICE_ID: z.string().optional().default(""),

  MASKED_ORIGINS: z
    .string()
    .optional()
    .default("")
    .transform((v) => v.split(",").map((s) => s.trim()).filter(Boolean)),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(raw: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join(".")}: ${i.message}`)
      .join("; ");
    throw new Error(`Invalid environment: ${issues}`);
  }
  return parsed.data;
}

export const env = loadEnv();
