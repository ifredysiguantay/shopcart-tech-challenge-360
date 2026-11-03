import { hashPassword } from "../auth/security.js";
import type { Pagination } from "../../shared/pagination.js";
import { toPage } from "../../shared/pagination.js";
import { usersRepository } from "./users.repository.js";

export const usersService = {
  async create(input: { correo: string; password: string; nombre: string; idRol: number }) {
    const passwordHash = await hashPassword(input.password);
    return usersRepository.create({ ...input, passwordHash });
  },

  async list(pagination: Pagination) {
    return toPage(await usersRepository.list(pagination), pagination);
  },

  changeStatus: usersRepository.changeStatus,
};
