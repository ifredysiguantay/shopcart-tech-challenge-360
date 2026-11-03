import { param, queryOne, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export const usersRepository = {
  create(input: { correo: string; passwordHash: string; nombre: string; idRol: number }): Promise<Row | undefined> {
    return queryOne("SP_Usuarios_Crear", {
      Correo: param.text(input.correo, 256),
      PasswordHash: param.text(input.passwordHash, 255),
      Nombre: param.text(input.nombre, 100),
      IDRol: param.tinyInt(input.idRol),
    });
  },

  list({ page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Usuarios_Listar", { Pagina: param.int(page), TamanoPagina: param.int(pageSize) });
  },

  changeStatus(idUsuario: number, activo: boolean, idActor: number): Promise<Row | undefined> {
    return queryOne("SP_Usuarios_CambiarEstado", {
      IDUsuario: param.int(idUsuario),
      Activo: param.bit(activo),
      IDActor: param.int(idActor),
    });
  },
};
