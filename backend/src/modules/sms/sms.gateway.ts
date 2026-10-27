import twilio from "twilio";
import { env } from "../../config/env.js";
import { logger } from "../../lib/logger.js";

export interface SmsGateway {
  send(to: string, body: string): Promise<void>;
}

class TwilioSmsGateway implements SmsGateway {
  private readonly client: ReturnType<typeof twilio>;

  constructor() {
    this.client = twilio(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN);
  }

  async send(to: string, body: string): Promise<void> {
    await this.client.messages.create({
      to,
      from: env.TWILIO_FROM_NUMBER,
      body,
    });
  }
}

class RestSmsGateway implements SmsGateway {
  async send(to: string, body: string): Promise<void> {
    const res = await fetch(env.SMS_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.SMS_API_KEY}`,
      },
      body: JSON.stringify({
        to,
        from: env.SMS_API_FROM,
        text: body,
      }),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`SMS API ${res.status}: ${text}`);
    }
  }
}

class LogSmsGateway implements SmsGateway {
  async send(to: string, body: string): Promise<void> {
    logger.warn({ to, body }, "SMS gateway not configured; OTP logged in development");
  }
}

export function createSmsGateway(): SmsGateway {
  if (env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM_NUMBER) {
    return new TwilioSmsGateway();
  }
  if (env.SMS_API_URL && env.SMS_API_KEY) {
    return new RestSmsGateway();
  }
  if (env.NODE_ENV !== "production") {
    return new LogSmsGateway();
  }
  throw new Error("No SMS gateway configured");
}
