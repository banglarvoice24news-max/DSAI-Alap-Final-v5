import type { Server, Socket } from "socket.io";
import { CallState, CallType } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import { logger } from "../../lib/logger.js";
import { tokenService } from "../auth/token.service.js";
import { messageService } from "../messages/message.service.js";
import { fcmService } from "../push/fcm.service.js";
import { presenceStore } from "./presence.store.js";

interface AuthedSocket extends Socket {
  userId: string;
  deviceId: string;
}

export function attachSignaling(io: Server): void {
  io.use((socket, next) => {
    try {
      const header =
        (socket.handshake.auth?.token as string | undefined) ||
        (socket.handshake.headers.authorization as string | undefined);
      const raw = header?.startsWith("Bearer ") ? header.slice(7) : header;
      if (!raw) {
        next(new Error("UNAUTHORIZED"));
        return;
      }
      const claims = tokenService.verifyAccess(raw);
      void tokenService.assertSession(claims.sid, claims.sub).then(
        () => {
          (socket as AuthedSocket).userId = claims.sub;
          (socket as AuthedSocket).deviceId = claims.deviceId;
          next();
        },
        () => next(new Error("UNAUTHORIZED")),
      );
    } catch {
      next(new Error("UNAUTHORIZED"));
    }
  });

  io.on("connection", (raw) => {
    const socket = raw as AuthedSocket;
    void onConnect(io, socket);
  });
}

async function onConnect(io: Server, socket: AuthedSocket): Promise<void> {
  await presenceStore.setOnline(socket.userId, socket.id);
  await prisma.user.update({
    where: { id: socket.userId },
    data: { lastSeenAt: new Date() },
  });
  socket.join(`user:${socket.userId}`);
  logger.info({ userId: socket.userId }, "socket connected");

  socket.on("presence:ping", async () => {
    await presenceStore.heartbeat(socket.userId, socket.id);
  });

  socket.on("call:offer", async (payload: { to: string; sdp: string; type: "AUDIO" | "VIDEO" }, ack?) => {
    try {
      const call = await prisma.call.create({
        data: {
          callerId: socket.userId,
          calleeId: payload.to,
          type: payload.type === "VIDEO" ? CallType.VIDEO : CallType.AUDIO,
          state: CallState.RINGING,
        },
      });
      const target = await presenceStore.getSocketId(payload.to);
      if (target) {
        io.to(target).emit("call:offer", {
          callId: call.id,
          from: socket.userId,
          sdp: payload.sdp,
          type: payload.type,
        });
      } else {
        const caller = await prisma.user.findUnique({
          where: { id: socket.userId },
          select: { displayName: true, phoneNumber: true },
        });
        await fcmService.notifyIncomingCall(
          payload.to,
          caller?.displayName || caller?.phoneNumber || "Nexus",
          call.id,
          payload.type,
        );
      }
      ack?.({ ok: true, callId: call.id });
    } catch (err) {
      logger.error({ err }, "call:offer failed");
      ack?.({ ok: false });
    }
  });

  socket.on("call:answer", async (payload: { callId: string; to: string; sdp: string }) => {
    await prisma.call.update({
      where: { id: payload.callId },
      data: { state: CallState.ACTIVE, startedAt: new Date() },
    });
    const target = await presenceStore.getSocketId(payload.to);
    if (target) {
      io.to(target).emit("call:answer", {
        callId: payload.callId,
        from: socket.userId,
        sdp: payload.sdp,
      });
    }
  });

  socket.on("call:ice", async (payload: { to: string; candidate: unknown; callId: string }) => {
    const target = await presenceStore.getSocketId(payload.to);
    if (target) {
      io.to(target).emit("call:ice", {
        callId: payload.callId,
        from: socket.userId,
        candidate: payload.candidate,
      });
    }
  });

  socket.on("call:hangup", async (payload: { callId: string; to: string; reason?: string }) => {
    const call = await prisma.call.findUnique({ where: { id: payload.callId } });
    if (!call) return;
    const nextState =
      call.state === CallState.RINGING
        ? payload.reason === "reject"
          ? CallState.REJECTED
          : CallState.MISSED
        : CallState.ENDED;
    await prisma.call.update({
      where: { id: payload.callId },
      data: { state: nextState, endedAt: new Date() },
    });
    if (nextState === CallState.MISSED) {
      const caller = await prisma.user.findUnique({
        where: { id: call.callerId },
        select: { displayName: true, phoneNumber: true },
      });
      await fcmService.notifyMissedCall(
        call.calleeId,
        caller?.displayName || caller?.phoneNumber || "Nexus",
        call.type,
      );
    }
    const target = await presenceStore.getSocketId(payload.to);
    if (target) {
      io.to(target).emit("call:hangup", { callId: payload.callId, from: socket.userId, reason: payload.reason });
    }
  });

  socket.on(
    "message:send",
    async (
      payload: { to: string; ciphertext: string; nonce?: string; header?: string; clientId?: string },
      ack?,
    ) => {
      try {
        const stored = await messageService.storeEncrypted({
          senderId: socket.userId,
          receiverId: payload.to,
          ciphertext: payload.ciphertext,
          nonce: payload.nonce,
          header: payload.header,
        });
        const target = await presenceStore.getSocketId(payload.to);
        if (target) {
          io.to(target).emit("message:incoming", {
            id: stored.id,
            from: socket.userId,
            ciphertext: stored.ciphertext,
            nonce: stored.nonce,
            header: stored.header,
            createdAt: stored.createdAt.toISOString(),
          });
        }
        ack?.({ ok: true, id: stored.id, status: "SENT", clientId: payload.clientId });
        socket.emit("message:receipt", { id: stored.id, status: "SENT", clientId: payload.clientId });
      } catch (err) {
        logger.error({ err }, "message:send failed");
        ack?.({ ok: false });
      }
    },
  );

  socket.on("message:delivered", async (payload: { id: string; to: string }) => {
    await messageService.markDelivered(payload.id, socket.userId);
    const target = await presenceStore.getSocketId(payload.to);
    if (target) {
      io.to(target).emit("message:receipt", { id: payload.id, status: "DELIVERED" });
    }
  });

  socket.on("message:read", async (payload: { ids: string[]; to: string }) => {
    await messageService.markRead(payload.ids, socket.userId);
    const target = await presenceStore.getSocketId(payload.to);
    if (target) {
      io.to(target).emit("message:receipt", { ids: payload.ids, status: "READ" });
    }
  });

  socket.on("e2ee:prekey", (payload: { to: string; bundle: unknown }) => {
    void presenceStore.getSocketId(payload.to).then((target) => {
      if (target) {
        io.to(target).emit("e2ee:prekey", { from: socket.userId, bundle: payload.bundle });
      }
    });
  });

  socket.on("disconnect", async () => {
    await presenceStore.setOffline(socket.id);
    await prisma.user.update({
      where: { id: socket.userId },
      data: { lastSeenAt: new Date() },
    });
    logger.info({ userId: socket.userId }, "socket disconnected");
  });
}
