import jwt from "jsonwebtoken";
import type { CookieOptions, Response } from "express";
import { env } from "../../config/env.js";
import { randomToken, sha256Hex } from "../../lib/crypto.js";
import { prisma } from "../../lib/prisma.js";
import { AppError } from "../../lib/http.js";

export interface AccessClaims {
  sub: string;
  phone: string;
  deviceId: string;
  sid: string;
}

const ACCESS_SECONDS = parseDurationSeconds(env.JWT_ACCESS_EXPIRES_IN, 15 * 60);
const REFRESH_SECONDS = parseDurationSeconds(env.JWT_REFRESH_EXPIRES_IN, 30 * 24 * 60 * 60);

function parseDurationSeconds(value: string, fallback: number): number {
  const match = /^(\d+)([smhd])$/.exec(value.trim());
  if (!match) return fallback;
  const amount = Number(match[1]);
  switch (match[2]) {
    case "s":
      return amount;
    case "m":
      return amount * 60;
    case "h":
      return amount * 3600;
    case "d":
      return amount * 86400;
    default:
      return fallback;
  }
}

function cookieOptions(): CookieOptions {
  return {
    httpOnly: true,
    secure: env.COOKIE_SECURE,
    sameSite: env.COOKIE_SAMESITE,
    domain: env.COOKIE_DOMAIN || undefined,
    path: "/api/auth",
    maxAge: REFRESH_SECONDS * 1000,
  };
}

export class TokenService {
  signAccess(claims: AccessClaims): string {
    return jwt.sign(claims, env.JWT_ACCESS_SECRET, {
      algorithm: "HS256",
      expiresIn: ACCESS_SECONDS,
      issuer: env.JWT_ISSUER,
      audience: env.JWT_AUDIENCE,
    });
  }

  verifyAccess(token: string): AccessClaims {
    try {
      return jwt.verify(token, env.JWT_ACCESS_SECRET, {
        algorithms: ["HS256"],
        issuer: env.JWT_ISSUER,
        audience: env.JWT_AUDIENCE,
      }) as AccessClaims;
    } catch {
      throw new AppError(401, "Invalid or expired access token", "ACCESS_TOKEN_INVALID");
    }
  }

  async assertSession(sid: string, userId: string): Promise<void> {
    const session = await prisma.session.findUnique({ where: { id: sid } });
    if (!session || session.userId !== userId || session.revokedAt || session.expiresAt < new Date()) {
      throw new AppError(401, "Session revoked", "SESSION_REVOKED");
    }
  }

  async issueSession(params: {
    userId: string;
    phone: string;
    deviceId: string;
    ip: string;
    userAgent?: string;
    res: Response;
  }): Promise<{ accessToken: string; refreshToken: string; expiresIn: number }> {
    const rawRefresh = randomToken(48);
    const hashed = sha256Hex(rawRefresh);
    const expiresAt = new Date(Date.now() + REFRESH_SECONDS * 1000);

    await prisma.session.updateMany({
      where: { userId: params.userId, deviceId: params.deviceId, revokedAt: null },
      data: { revokedAt: new Date() },
    });

    const session = await prisma.session.create({
      data: {
        userId: params.userId,
        refreshToken: hashed,
        deviceId: params.deviceId,
        ip: params.ip,
        userAgent: params.userAgent,
        expiresAt,
      },
    });

    params.res.cookie(env.REFRESH_COOKIE_NAME, rawRefresh, cookieOptions());

    const accessToken = this.signAccess({
      sub: params.userId,
      phone: params.phone,
      deviceId: params.deviceId,
      sid: session.id,
    });

    return { accessToken, refreshToken: rawRefresh, expiresIn: ACCESS_SECONDS };
  }

  async rotateRefresh(rawRefresh: string, ip: string, userAgent: string | undefined, res: Response) {
    const hashed = sha256Hex(rawRefresh);
    const session = await prisma.session.findUnique({
      where: { refreshToken: hashed },
      include: { user: true },
    });
    if (!session) {
      throw new AppError(401, "Refresh token invalid", "REFRESH_INVALID");
    }
    if (session.expiresAt < new Date()) {
      throw new AppError(401, "Refresh token invalid", "REFRESH_INVALID");
    }
    if (session.revokedAt) {
      await prisma.session.updateMany({
        where: { userId: session.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      throw new AppError(401, "Refresh token reuse detected", "REFRESH_REUSE");
    }

    await prisma.session.update({
      where: { id: session.id },
      data: { revokedAt: new Date() },
    });

    return this.issueSession({
      userId: session.userId,
      phone: session.user.phoneNumber,
      deviceId: session.deviceId,
      ip,
      userAgent,
      res,
    });
  }

  async revokeRefresh(rawRefresh: string, res: Response): Promise<void> {
    const hashed = sha256Hex(rawRefresh);
    await prisma.session.updateMany({
      where: { refreshToken: hashed, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    res.clearCookie(env.REFRESH_COOKIE_NAME, {
      httpOnly: true,
      secure: env.COOKIE_SECURE,
      sameSite: env.COOKIE_SAMESITE,
      domain: env.COOKIE_DOMAIN || undefined,
      path: "/api/auth",
    });
  }
}

export const tokenService = new TokenService();
