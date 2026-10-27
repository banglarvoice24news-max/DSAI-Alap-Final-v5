import { PrismaClient } from "@prisma/client";
import { env } from "../config/env.js";
import { logger } from "./logger.js";

export const prisma = new PrismaClient({
  log: env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
});

export async function connectPrisma(): Promise<void> {
  await prisma.$connect();
  logger.info("postgres connected");
}

export async function disconnectPrisma(): Promise<void> {
  await prisma.$disconnect();
}
