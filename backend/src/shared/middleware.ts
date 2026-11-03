import type { NextFunction, Request, RequestHandler, Response } from "express";
import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { AppError, forbidden, toAppError, unauthorized } from "./errors.js";
import type { RoleId } from "./roles.js";

export interface AuthUser {
  id: number;
  rol: RoleId;
  correo: string;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

function readBearerToken(req: Request): string | undefined {
  const header = req.headers.authorization;
  return header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : undefined;
}

function verifyAccessToken(token: string): AuthUser {
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as jwt.JwtPayload;
    return { id: Number(payload.sub), rol: payload["rol"] as RoleId, correo: String(payload["correo"]) };
  } catch (error) {
    const message = error instanceof jwt.TokenExpiredError ? "El token expiró." : "Token inválido.";
    throw unauthorized(message);
  }
}

export const authenticate: RequestHandler = (req, _res, next) => {
  const token = readBearerToken(req);
  if (!token) throw unauthorized();
  req.user = verifyAccessToken(token);
  next();
};

export const optionalAuthenticate: RequestHandler = (req, _res, next) => {
  const token = readBearerToken(req);
  if (token) req.user = verifyAccessToken(token);
  next();
};

export function authorize(...roles: RoleId[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) throw unauthorized();
    if (!roles.includes(req.user.rol)) throw forbidden();
    next();
  };
}

export function requireUser(req: Request): AuthUser {
  if (!req.user) throw unauthorized();
  return req.user;
}

export const notFoundHandler: RequestHandler = (req) => {
  throw new AppError(404, `Ruta no encontrada: ${req.method} ${req.path}`, "NOT_FOUND");
};

export function errorHandler(error: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const appError = toAppError(error);
  if (appError.status >= 500) console.error(error);
  res.status(appError.status).json({
    error: { code: appError.code, message: appError.message, ...(appError.details ? { details: appError.details } : {}) },
  });
}
