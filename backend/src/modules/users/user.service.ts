import { Language } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import { AppError } from "../../lib/http.js";

export class UserService {
  async me(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        phoneNumber: true,
        publicKey: true,
        identityKey: true,
        displayName: true,
        avatarUrl: true,
        about: true,
        language: true,
        createdAt: true,
        lastSeenAt: true,
      },
    });
    if (!user) throw new AppError(404, "User not found", "USER_NOT_FOUND");
    return user;
  }

  async updateProfile(
    userId: string,
    data: { displayName?: string; about?: string; avatarUrl?: string; language?: Language },
  ) {
    return prisma.user.update({
      where: { id: userId },
      data,
      select: {
        id: true,
        displayName: true,
        about: true,
        avatarUrl: true,
        language: true,
      },
    });
  }

  async lookupByPhone(phoneNumber: string) {
    const user = await prisma.user.findUnique({
      where: { phoneNumber },
      select: { id: true, displayName: true, publicKey: true, avatarUrl: true, language: true },
    });
    if (!user) throw new AppError(404, "User not found", "USER_NOT_FOUND");
    return user;
  }

  async block(blockerId: string, blockedId: string) {
    if (blockerId === blockedId) throw new AppError(400, "Cannot block self", "INVALID");
    await prisma.blockedContact.upsert({
      where: { blockerId_blockedId: { blockerId, blockedId } },
      create: { blockerId, blockedId },
      update: {},
    });
  }

  async unblock(blockerId: string, blockedId: string) {
    await prisma.blockedContact.deleteMany({ where: { blockerId, blockedId } });
  }

  async blockedList(blockerId: string) {
    return prisma.blockedContact.findMany({
      where: { blockerId },
      include: {
        blocked: { select: { id: true, displayName: true, phoneNumber: true } },
      },
    });
  }
}

export const userService = new UserService();
