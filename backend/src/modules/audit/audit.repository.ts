import { param, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export const auditRepository = {
  list(modulo: string | undefined, { page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Bitacora_Listar", {
      Modulo: param.text(modulo, 30),
      Pagina: param.int(page),
      TamanoPagina: param.int(pageSize),
    });
  },
};
