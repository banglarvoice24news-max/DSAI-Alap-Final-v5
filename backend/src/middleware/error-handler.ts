import type { NextFunction, Request, Response } from "express";
import { ZodError } from "zod";
import { AppError, fail } from "../lib/http.js";
import { logger } from "../lib/logger.js";

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof AppError) {
    fail(res, err.status, err.code, err.message);
    return;
  }
  if (err instanceof ZodError) {
    fail(res, 400, "VALIDATION_ERROR", err.issues.map((i) => i.message).join(", "));
    return;
  }
  logger.error({ err }, "unhandled error");
  fail(res, 500, "INTERNAL", "Internal server error");
}
