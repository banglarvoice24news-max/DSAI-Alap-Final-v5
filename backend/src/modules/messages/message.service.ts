import { MessageStatus } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import { AppError } from "../../lib/http.js";
import { fcmService } from "../push/fcm.service.js";
import { summarizeThreads, type MessageThreadSummary } from "./threads.js";

export class MessageService {
  async storeEncrypted(params: {
    senderId: string;
    receiverId: string;
    ciphertext: string;
    nonce?: string;
    header?: string;
  }) {
    if (params.senderId === params.receiverId) {
      throw new AppError(400, "Cannot message self", "INVALID_RECEIVER");
    }
    const blocked = await prisma.blockedContact.findFirst({
      where: {
        OR: [
          { blockerId: params.receiverId, blockedId: params.senderId },
          { blockerId: params.senderId, blockedId: params.receiverId },
        ],
      },
    });
    if (blocked) {
      throw new AppError(403, "Messaging blocked", "BLOCKED");
    }

    const message = await prisma.message.create({
      data: {
        senderId: params.senderId,
        receiverId: params.receiverId,
        ciphertext: params.ciphertext,
        nonce: params.nonce,
        header: params.header,
        status: MessageStatus.SENT,
      },
    });

    const sender = await prisma.user.findUnique({
      where: { id: params.senderId },
      select: { displayName: true, phoneNumber: true },
    });
    await fcmService.notifyMessage(
      params.receiverId,
      sender?.displayName || sender?.phoneNumber || "Nexus",
    );
    return message;
  }

  async markDelivered(messageId: string, receiverId: string) {
    const updated = await prisma.message.updateMany({
      where: { id: messageId, receiverId, status: MessageStatus.SENT },
      data: { status: MessageStatus.DELIVERED, deliveredAt: new Date() },
    });
    if (updated.count === 0) {
      throw new AppError(404, "Message not found", "MESSAGE_NOT_FOUND");
    }
  }

  async markRead(messageIds: string[], receiverId: string) {
    await prisma.message.updateMany({
      where: {
        id: { in: messageIds },
        receiverId,
        status: { in: [MessageStatus.SENT, MessageStatus.DELIVERED] },
      },
      data: { status: MessageStatus.READ, readAt: new Date() },
    });
  }

  async inbox(userId: string, cursor?: string, take = 50) {
    return prisma.message.findMany({
      where: {
        OR: [{ senderId: userId }, { receiverId: userId }],
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      orderBy: { createdAt: "desc" },
      take,
    });
  }

  /**
   * Per-counterpart thread summaries for the chat list. The client never needs
   * plaintext here: it only groups by the other party and shows when, whether
   * it was ours and how many are unread. Message bodies stay encrypted.
   *
   * Note: unreadCount is derived from the fetched window (the most recent
   * messages), so a very old unread message outside the window is not counted.
   */
  async threads(userId: string, take = 50): Promise<MessageThreadSummary[]> {
    const messages = await prisma.message.findMany({
      where: { OR: [{ senderId: userId }, { receiverId: userId }] },
      orderBy: { createdAt: "desc" },
      take: 500,
    });
    const counterpartIds = [
      ...new Set(messages.map((message) => (message.senderId === userId ? message.receiverId : message.senderId))),
    ];
    if (counterpartIds.length === 0) return [];
    const users = await prisma.user.findMany({
      where: { id: { in: counterpartIds } },
      select: { id: true, displayName: true, phoneNumber: true },
    });
    return summarizeThreads(messages, new Map(users.map((user) => [user.id, user])), userId).slice(0, take);
  }
}

export const messageService = new MessageService();
