import http from "node:http";
import { Server } from "socket.io";
import { env } from "./config/env.js";
import { logger } from "./lib/logger.js";
import { connectPrisma, disconnectPrisma } from "./lib/prisma.js";
import { disconnectRedis } from "./lib/redis.js";
import { createApp } from "./app.js";
import { attachSignaling } from "./modules/signaling/signaling.gateway.js";
import { webhookDispatcher } from "./services/b2b/webhook.dispatcher.js";
import { startWebhookRetryLoop } from "./services/b2b/webhook.queue.js";

async function main(): Promise<void> {
  await connectPrisma();
  const app = await createApp();
  const server = http.createServer(app);
  const io = new Server(server, {
    cors: { origin: [...env.CORS_ORIGINS, ...env.MASKED_ORIGINS], credentials: true },
    pingInterval: env.SIGNALING_PING_INTERVAL_MS,
    pingTimeout: 20000,
    maxHttpBufferSize: env.SIGNALING_MAX_BUFFER_SIZE,
    perMessageDeflate: false,
    allowEIO3: false,
  });
  attachSignaling(io);
  startWebhookRetryLoop((event, url) => webhookDispatcher.deliver(event, url));

  // §3.2: only the CPaaS layer consumes the dedicated call-event channel. ESL
  // itself is started lazily by the first GSM call so a boot without
  // FreeSWITCH still serves the rest of the app.
  const stopCpaas = await startCpaasLayer();

  server.listen(env.PORT, env.HOST, () => {
    logger.info({ host: env.HOST, port: env.PORT }, "nexus api listening");
  });

  const shutdown = async (signal: string) => {
    logger.info({ signal }, "shutting down");
    await stopCpaas();
    io.close();
    server.close();
    await disconnectPrisma();
    await disconnectRedis();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

/**
 * Start the background CDR/status consumer when the CPaaS layer is enabled.
 * Returns an async stop function (no-op when the layer is off).
 */
async function startCpaasLayer(): Promise<() => Promise<void>> {
  if (!env.ENABLE_CPAAS_LAYER) {
    return async () => undefined;
  }
  const [{ callEventConsumer }, { eslClient }] = await Promise.all([
    import("./services/telecom/call-events.consumer.js"),
    import("./services/telecom/freeswitch_esl.service.js"),
  ]);
  await callEventConsumer.start();
  eslClient.start();
  logger.info("cpaas layer enabled: call event consumer + FreeSWITCH ESL started");
  return async () => {
    await callEventConsumer.stop();
    await eslClient.stop();
  };
}

main().catch((err) => {
  logger.fatal({ err }, "failed to start");
  process.exit(1);
});
