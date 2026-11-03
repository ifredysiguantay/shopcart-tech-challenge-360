import { execute, param, queryOne } from "../../database/procedures.js";

export interface UserRecord {
  idUsuario: number;
  correo: string;
  nombre: string;
  idRol: number;
  passwordHash?: string;
  activo?: boolean;
}

export const authRepository = {
  async registerCustomer(correo: string, passwordHash: string, nombre: string): Promise<UserRecord> {
    const row = await queryOne("SP_Auth_RegistrarCliente", {
      Correo: param.text(correo, 256),
      PasswordHash: param.text(passwordHash, 255),
      Nombre: param.text(nombre, 100),
    });
    return row as unknown as UserRecord;
  },

  async findByEmail(correo: string): Promise<UserRecord | undefined> {
    const row = await queryOne("SP_Auth_ObtenerPorCorreo", { Correo: param.text(correo, 256) });
    return row as unknown as UserRecord | undefined;
  },

  async findById(idUsuario: number): Promise<(UserRecord & { rol: string }) | undefined> {
    const row = await queryOne("SP_Auth_ObtenerPorID", { IDUsuario: param.int(idUsuario) });
    return row as unknown as (UserRecord & { rol: string }) | undefined;
  },

  async saveRefreshToken(idUsuario: number, hash: string, expiresAt: Date): Promise<void> {
    await execute("SP_Auth_GuardarRefreshToken", {
      IDUsuario: param.int(idUsuario),
      TokenHash: param.char(hash, 64),
      FechaExpiracion: param.dateTime(expiresAt),
    });
  },

  async rotateRefreshToken(currentHash: string, newHash: string, expiresAt: Date): Promise<UserRecord> {
    const row = await queryOne("SP_Auth_RotarRefreshToken", {
      TokenHashActual: param.char(currentHash, 64),
      TokenHashNuevo: param.char(newHash, 64),
      FechaExpiracion: param.dateTime(expiresAt),
    });
    return row as unknown as UserRecord;
  },

  async revokeRefreshToken(hash: string): Promise<void> {
    await execute("SP_Auth_RevocarRefreshToken", { TokenHash: param.char(hash, 64) });
  },
};
