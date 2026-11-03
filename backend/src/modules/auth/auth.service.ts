import { env } from "../../config/env.js";
import { AppError, unauthorized } from "../../shared/errors.js";
import { cartRepository } from "../cart/cart.repository.js";
import { authRepository, type UserRecord } from "./auth.repository.js";
import { createRefreshToken, hashPassword, hashRefreshToken, signAccessToken, verifyPassword } from "./security.js";

export interface Session {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  user: { id: number; correo: string; nombre: string; rol: number };
}

async function openSession(user: UserRecord): Promise<Session> {
  const refresh = createRefreshToken();
  await authRepository.saveRefreshToken(user.idUsuario, refresh.hash, refresh.expiresAt);
  return buildSession(user, refresh.token);
}

function buildSession(user: UserRecord, refreshToken: string): Session {
  return {
    accessToken: signAccessToken({ id: user.idUsuario, rol: user.idRol, correo: user.correo }),
    refreshToken,
    expiresIn: env.JWT_ACCESS_TTL,
    user: { id: user.idUsuario, correo: user.correo, nombre: user.nombre, rol: user.idRol },
  };
}

export const authService = {
  async register(input: { correo: string; password: string; nombre: string }): Promise<Session> {
    const passwordHash = await hashPassword(input.password);
    const user = await authRepository.registerCustomer(input.correo, passwordHash, input.nombre);
    return openSession(user);
  },

  async login(input: { correo: string; password: string }, guestCartToken?: string): Promise<Session> {
    const user = await authRepository.findByEmail(input.correo);
    const valid = user?.passwordHash ? await verifyPassword(input.password, user.passwordHash) : false;
    if (!user || !valid || !user.activo) throw new AppError(401, "Credenciales inválidas.", "UNAUTHORIZED");

    if (guestCartToken) await cartRepository.mergeGuestCart(user.idUsuario, guestCartToken);
    return openSession(user);
  },

  async refresh(refreshToken: string): Promise<Session> {
    const next = createRefreshToken();
    const user = await authRepository.rotateRefreshToken(hashRefreshToken(refreshToken), next.hash, next.expiresAt);
    return buildSession(user, next.token);
  },

  async logout(refreshToken: string): Promise<void> {
    await authRepository.revokeRefreshToken(hashRefreshToken(refreshToken));
  },

  async currentUser(idUsuario: number) {
    const user = await authRepository.findById(idUsuario);
    if (!user || !user.activo) throw unauthorized("Usuario inactivo.");
    return { id: user.idUsuario, correo: user.correo, nombre: user.nombre, rol: user.idRol };
  },
};
