// Pure chat-thread summarisation. Kept free of Prisma/Redis imports so it can
// be unit-tested without a database.

import { MessageStatus } from "@prisma/client";

export interface MessageThreadSummary {
  counterpartId: string;
  counterpartName: string | null;
  lastMessageId: string;
  lastStatus: MessageStatus;
  lastMessageAt: Date;
  lastMessageMine: boolean;
  unreadCount: number;
}

export type ThreadableMessage = {
  id: string;
  senderId: string;
  receiverId: string;
  status: MessageStatus;
  createdAt: Date;
};

export type ThreadableUser = {
  id: string;
  displayName: string | null;
  phoneNumber: string;
};

/**
 * Collapses a user's message rows into one summary per counterpart. Input is
 * expected newest-first, so the first row seen for a counterpart becomes that
 * thread's "last message".
 */
export function summarizeThreads(
  messages: ThreadableMessage[],
  users: Map<string, ThreadableUser>,
  userId: string,
): MessageThreadSummary[] {
  const threads = new Map<string, MessageThreadSummary>();
  const unread = new Map<string, number>();

  for (const message of messages) {
    const counterpartId = message.senderId === userId ? message.receiverId : message.senderId;
    if (message.receiverId === userId && message.status !== MessageStatus.READ) {
      unread.set(counterpartId, (unread.get(counterpartId) ?? 0) + 1);
    }
    if (threads.has(counterpartId)) continue;
    const user = users.get(counterpartId);
    threads.set(counterpartId, {
      counterpartId,
      counterpartName: user?.displayName || user?.phoneNumber || null,
      lastMessageId: message.id,
      lastStatus: message.status,
      lastMessageAt: message.createdAt,
      lastMessageMine: message.senderId === userId,
      unreadCount: 0,
    });
  }

  return [...threads.values()].map((thread) => ({
    ...thread,
    unreadCount: unread.get(thread.counterpartId) ?? 0,
  }));
}
