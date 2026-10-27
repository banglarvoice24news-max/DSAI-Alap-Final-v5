import { prisma } from "../../lib/prisma.js";
import { AppError } from "../../lib/http.js";

export interface PreKeyBundle {
  userId: string;
  identityKey: string;
  signedPreKey: string;
  signedPreKeySig: string;
  oneTimePreKey?: { keyId: number; publicKey: string };
  registrationPublicKey: string;
}

export class E2eeService {
  async publishBundle(userId: string, bundle: {
    identityKey: string;
    signedPreKey: string;
    signedPreKeySig: string;
    publicKey: string;
    oneTimePreKeys: { keyId: number; publicKey: string }[];
  }): Promise<void> {
    await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: {
          identityKey: bundle.identityKey,
          signedPreKey: bundle.signedPreKey,
          signedPreKeySig: bundle.signedPreKeySig,
          publicKey: bundle.publicKey,
        },
      });
      if (bundle.oneTimePreKeys.length > 0) {
        await tx.oneTimePreKey.createMany({
          data: bundle.oneTimePreKeys.map((k) => ({
            userId,
            keyId: k.keyId,
            publicKey: k.publicKey,
          })),
          skipDuplicates: true,
        });
      }
    });
  }

  async fetchBundle(targetUserId: string): Promise<PreKeyBundle> {
    const user = await prisma.user.findUnique({
      where: { id: targetUserId },
      include: {
        oneTimePreKeys: {
          where: { consumed: false },
          orderBy: { keyId: "asc" },
          take: 1,
        },
      },
    });
    if (!user) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }
    if (!user.identityKey || !user.signedPreKey || !user.signedPreKeySig) {
      throw new AppError(409, "Peer has not published an E2EE bundle", "E2EE_BUNDLE_MISSING");
    }

    let otpk: { keyId: number; publicKey: string } | undefined;
    const first = user.oneTimePreKeys[0];
    if (first) {
      await prisma.oneTimePreKey.update({
        where: { id: first.id },
        data: { consumed: true },
      });
      otpk = { keyId: first.keyId, publicKey: first.publicKey };
    }

    return {
      userId: user.id,
      identityKey: user.identityKey,
      signedPreKey: user.signedPreKey,
      signedPreKeySig: user.signedPreKeySig,
      oneTimePreKey: otpk,
      registrationPublicKey: user.publicKey,
    };
  }

  async remainingPreKeys(userId: string): Promise<number> {
    return prisma.oneTimePreKey.count({ where: { userId, consumed: false } });
  }
}

export const e2eeService = new E2eeService();
