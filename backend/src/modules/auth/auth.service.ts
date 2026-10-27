import { Language } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import { AppError } from "../../lib/http.js";
import { otpService } from "./otp.service.js";
import { tokenService } from "./token.service.js";
import { backupService } from "./backup.service.js";
import type { Response } from "express";

export class AuthService {
  async requestOtp(phoneNumber: string) {
    return otpService.requestOtp(phoneNumber);
  }

  async verifyOtp(params: {
    phoneNumber: string;
    otp: string;
    deviceId: string;
    publicKey: string;
    identityKey?: string;
    signedPreKey?: string;
    signedPreKeySig?: string;
    displayName?: string;
    language?: Language;
    ip: string;
    userAgent?: string;
    res: Response;
  }) {
    await otpService.verifyOtp(params.phoneNumber, params.otp);

    const user = await prisma.user.upsert({
      where: { phoneNumber: params.phoneNumber },
      create: {
        phoneNumber: params.phoneNumber,
        publicKey: params.publicKey,
        identityKey: params.identityKey,
        signedPreKey: params.signedPreKey,
        signedPreKeySig: params.signedPreKeySig,
        displayName: params.displayName,
        language: params.language ?? Language.en,
      },
      update: {
        publicKey: params.publicKey,
        identityKey: params.identityKey,
        signedPreKey: params.signedPreKey,
        signedPreKeySig: params.signedPreKeySig,
        lastSeenAt: new Date(),
      },
    });

    const tokens = await tokenService.issueSession({
      userId: user.id,
      phone: user.phoneNumber,
      deviceId: params.deviceId,
      ip: params.ip,
      userAgent: params.userAgent,
      res: params.res,
    });

    return { user, ...tokens };
  }

  async refresh(rawRefresh: string | undefined, ip: string, userAgent: string | undefined, res: Response) {
    if (!rawRefresh) {
      throw new AppError(401, "Missing refresh cookie", "REFRESH_MISSING");
    }
    return tokenService.rotateRefresh(rawRefresh, ip, userAgent, res);
  }

  async logout(rawRefresh: string | undefined, res: Response) {
    if (rawRefresh) {
      await tokenService.revokeRefresh(rawRefresh, res);
    }
  }

  async setBackupKey(userId: string, backupKey: string) {
    await backupService.registerBackupKey(userId, backupKey);
  }

  async startBackupRestore(phoneNumber: string) {
    return backupService.startRestore(phoneNumber);
  }

  async completeBackupRestore(params: {
    challengeId: string;
    backupKey: string;
    deviceId: string;
    ip: string;
    userAgent?: string;
    res: Response;
  }) {
    const restored = await backupService.completeRestore(params.challengeId, params.backupKey);
    return tokenService.issueSession({
      userId: restored.userId,
      phone: restored.phoneNumber,
      deviceId: params.deviceId,
      ip: params.ip,
      userAgent: params.userAgent,
      res: params.res,
    });
  }
}

export const authService = new AuthService();
