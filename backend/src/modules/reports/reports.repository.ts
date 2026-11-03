import { env } from "../../config/env.js";
import { execute, param, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export interface DateRange {
  from: Date;
  to: Date;
}

const rangeParams = ({ from, to }: DateRange) => ({ Desde: param.date(from), Hasta: param.date(to) });

export const reportsRepository = {
  async summary(range: DateRange) {
    const [totals, carts] = await execute("SP_Reportes_Resumen", {
      ...rangeParams(range),
      MinutosAbandono: param.int(env.CART_ABANDON_MINUTES),
    });
    return { ...totals?.[0], ...carts?.[0] };
  },

  salesByPeriod(grouping: string, range: DateRange): Promise<Row[]> {
    return queryRows("SP_Reportes_VentasPorPeriodo", { Agrupacion: param.text(grouping, 10), ...rangeParams(range) });
  },

  salesByCategory(range: DateRange): Promise<Row[]> {
    return queryRows("SP_Reportes_VentasPorCategoria", rangeParams(range));
  },

  topProducts(range: DateRange, top: number): Promise<Row[]> {
    return queryRows("SP_Reportes_TopProductos", { ...rangeParams(range), Top: param.int(top) });
  },

  abandonedCarts({ page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Reportes_CarritosAbandonados", {
      MinutosAbandono: param.int(env.CART_ABANDON_MINUTES),
      Pagina: param.int(page),
      TamanoPagina: param.int(pageSize),
    });
  },
};
