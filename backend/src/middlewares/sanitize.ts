import type { NextFunction, Request, Response } from "express";

const FORBIDDEN = new Set(["__proto__", "prototype", "constructor"]);
const MAX_DEPTH = 8;
const MAX_KEYS = 64;
const MAX_STRING = 4096;

function stripControlChars(value: string): string {
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "").slice(0, MAX_STRING);
}

function sanitizeValue(value: unknown, depth: number): unknown {
  if (depth > MAX_DEPTH || value == null) return value;
  if (typeof value === "string") return stripControlChars(value);
  if (typeof value !== "object") return value;
  if (Array.isArray(value)) {
    return value.slice(0, 100).map((item) => sanitizeValue(item, depth + 1));
  }
  const src = value as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  let count = 0;
  for (const key of Object.keys(src)) {
    if (FORBIDDEN.has(key)) continue;
    if (count++ >= MAX_KEYS) break;
    out[key] = sanitizeValue(src[key], depth + 1);
  }
  return out;
}

export function sanitizeBody(req: Request, _res: Response, next: NextFunction): void {
  if (req.body && typeof req.body === "object") {
    req.body = sanitizeValue(req.body, 0);
  }
  if (req.query && typeof req.query === "object") {
    req.query = sanitizeValue(req.query, 0) as typeof req.query;
  }
  next();
}
