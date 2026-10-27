import { randomBytes } from "node:crypto";
import { env } from "../../config/env.js";
import { redis } from "../../lib/redis.js";
import { prisma } from "../../lib/prisma.js";
import { generateBackupSalt, hashBackupKey, safeEqualHex } from "../../lib/crypto.js";
import { AppError } from "../../lib/http.js";

const CHALLENGE_PREFIX = "backup_challenge:";

export class BackupService {
  async registerBackupKey(userId: string, backupKey: string): Promise<void> {
    const salt = generateBackupSalt();
    const hash = hashBackupKey(backupKey, salt, env.BACKUP_KEY_PEPPER);
    await prisma.user.update({
      where: { id: userId },
      data: { backupKeyHash: hash, backupKeySalt: salt },
    });
  }

  async startRestore(phoneNumber: string): Promise<{ challengeId: string; nonce: string }> {
    const user = await prisma.user.findUnique({ where: { phoneNumber } });
    if (!user?.backupKeyHash || !user.backupKeySalt) {
      throw new AppError(404, "No offline backup registered for this account", "BACKUP_NOT_FOUND");
    }
    const challengeId = randomBytes(16).toString("hex");
    const nonce = randomBytes(16).toString("hex");
    await redis.set(
      `${CHALLENGE_PREFIX}${challengeId}`,
      JSON.stringify({ phoneNumber, nonce, userId: user.id }),
      "EX",
      env.BACKUP_CHALLENGE_TTL_SECONDS,
    );
    return { challengeId, nonce };
  }

  async completeRestore(challengeId: string, backupKey: string): Promise<{ userId: string; phoneNumber: string }> {
    const raw = await redis.get(`${CHALLENGE_PREFIX}${challengeId}`);
    if (!raw) {
      throw new AppError(400, "Backup challenge expired", "BACKUP_CHALLENGE_EXPIRED");
    }
    const challenge = JSON.parse(raw) as { phoneNumber: string; userId: string };
    const user = await prisma.user.findUnique({ where: { id: challenge.userId } });
    if (!user?.backupKeyHash || !user.backupKeySalt) {
      throw new AppError(404, "Backup key missing", "BACKUP_NOT_FOUND");
    }
    const incoming = hashBackupKey(backupKey, user.backupKeySalt, env.BACKUP_KEY_PEPPER);
    if (!safeEqualHex(incoming, user.backupKeyHash)) {
      throw new AppError(401, "Invalid backup key", "BACKUP_KEY_INVALID");
    }
    await redis.del(`${CHALLENGE_PREFIX}${challengeId}`);
    return { userId: user.id, phoneNumber: user.phoneNumber };
  }
}

export const backupService = new BackupService();
