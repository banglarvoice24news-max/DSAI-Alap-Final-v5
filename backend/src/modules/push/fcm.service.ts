import admin from "firebase-admin";
import { env } from "../../config/env.js";
import { logger } from "../../lib/logger.js";
import { prisma } from "../../lib/prisma.js";

let initialized = false;

function initFcm(): void {
  if (initialized) return;
  if (admin.apps.length > 0) {
    initialized = true;
    return;
  }
  if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: env.FCM_PROJECT_ID,
        clientEmail: env.FCM_CLIENT_EMAIL,
        privateKey: env.FCM_PRIVATE_KEY.replace(/\\n/g, "\n"),
      }),
    });
    initialized = true;
    return;
  }
  if (env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    initialized = true;
  }
}

export class FcmService {
  isReady(): boolean {
    initFcm();
    return initialized;
  }

  async registerToken(userId: string, token: string): Promise<void> {
    await prisma.user.update({ where: { id: userId }, data: { fcmToken: token } });
  }

  async notifyMessage(receiverId: string, senderName: string): Promise<void> {
    await this.send(receiverId, {
      title: senderName,
      body: "New encrypted message",
      data: { type: "incoming_message" },
    });
  }

  async notifyMissedCall(receiverId: string, callerName: string, callType: string): Promise<void> {
    await this.send(receiverId, {
      title: "Missed call",
      body: `${callerName} tried to ${callType === "VIDEO" ? "video" : "voice"} call you`,
      data: { type: "missed_call", callType },
    });
  }

  async notifyIncomingCall(receiverId: string, callerName: string, callId: string, callType: string): Promise<void> {
    await this.send(receiverId, {
      title: `Incoming ${callType.toLowerCase()} call`,
      body: callerName,
      data: { type: "incoming_call", callId, callType },
    });
  }

  private async send(
    userId: string,
    payload: { title: string; body: string; data: Record<string, string> },
  ): Promise<void> {
    if (!this.isReady()) {
      logger.warn("FCM not configured; skip push");
      return;
    }
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { fcmToken: true } });
    if (!user?.fcmToken) return;
    try {
      await admin.messaging().send({
        token: user.fcmToken,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default", contentAvailable: true } } },
      });
    } catch (err) {
      logger.error({ err, userId }, "FCM send failed");
    }
  }
}

export const fcmService = new FcmService();
