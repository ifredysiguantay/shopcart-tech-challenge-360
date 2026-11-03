import { param, queryOne, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export const inventoryRepository = {
  list(texto: string | undefined, { page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Inventario_Listar", {
      Texto: param.text(texto, 100),
      Pagina: param.int(page),
      TamanoPagina: param.int(pageSize),
    });
  },

  kardex(idVariante: number, { page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Inventario_Kardex", {
      IDVariante: param.int(idVariante),
      Pagina: param.int(page),
      TamanoPagina: param.int(pageSize),
    });
  },

  registerMovement(
    input: { idVariante: number; tipo: "Entrada" | "Ajuste"; cantidad: number; motivo: string },
    idUsuario: number,
  ): Promise<Row | undefined> {
    return queryOne("SP_Inventario_RegistrarMovimiento", {
      IDVariante: param.int(input.idVariante),
      Tipo: param.text(input.tipo, 12),
      Cantidad: param.int(input.cantidad),
      Motivo: param.text(input.motivo, 250),
      IDUsuario: param.int(idUsuario),
    });
  },
};
