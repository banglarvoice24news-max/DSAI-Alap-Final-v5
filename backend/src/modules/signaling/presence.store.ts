import { redis } from "../../lib/redis.js";

const SOCKET_KEY = (userId: string) => `presence:user:${userId}`;
const USER_KEY = (socketId: string) => `presence:sock:${socketId}`;

export class PresenceStore {
  async setOnline(userId: string, socketId: string): Promise<void> {
    await redis.set(SOCKET_KEY(userId), socketId, "EX", 120);
    await redis.set(USER_KEY(socketId), userId, "EX", 120);
  }

  async heartbeat(userId: string, socketId: string): Promise<void> {
    await this.setOnline(userId, socketId);
  }

  async getSocketId(userId: string): Promise<string | null> {
    return redis.get(SOCKET_KEY(userId));
  }

  async getUserId(socketId: string): Promise<string | null> {
    return redis.get(USER_KEY(socketId));
  }

  async setOffline(socketId: string): Promise<string | null> {
    const userId = await redis.get(USER_KEY(socketId));
    if (userId) {
      const current = await redis.get(SOCKET_KEY(userId));
      if (current === socketId) {
        await redis.del(SOCKET_KEY(userId));
      }
    }
    await redis.del(USER_KEY(socketId));
    return userId;
  }
}

export const presenceStore = new PresenceStore();
