import { execute, param, queryOne, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export interface CouponInput {
  tipo: "Porcentaje" | "MontoFijo";
  valor: number;
  fechaInicio: Date;
  fechaFin: Date;
  montoMinimo: number;
  limiteUsosTotal: number;
  limiteUsosPorCliente: number;
  idCategoria?: number | undefined;
}

function couponParams(input: CouponInput) {
  return {
    Tipo: param.text(input.tipo, 12),
    Valor: param.money(input.valor),
    FechaInicio: param.dateTime(input.fechaInicio),
    FechaFin: param.dateTime(input.fechaFin),
    MontoMinimo: param.money(input.montoMinimo),
    LimiteUsosTotal: param.int(input.limiteUsosTotal),
    LimiteUsosPorCliente: param.int(input.limiteUsosPorCliente),
    IDCategoria: param.int(input.idCategoria),
  };
}

export const couponsRepository = {
  create(codigo: string, input: CouponInput, idUsuario: number): Promise<Row | undefined> {
    return queryOne("SP_Cupones_Crear", {
      Codigo: param.text(codigo, 30),
      ...couponParams(input),
      IDUsuario: param.int(idUsuario),
    });
  },

  async update(idCupon: number, input: CouponInput & { activo: boolean }, idUsuario: number): Promise<void> {
    await execute("SP_Cupones_Actualizar", {
      IDCupon: param.int(idCupon),
      ...couponParams(input),
      Activo: param.bit(input.activo),
      IDUsuario: param.int(idUsuario),
    });
  },

  list({ page, pageSize }: Pagination): Promise<Row[]> {
    return queryRows("SP_Cupones_Listar", { Pagina: param.int(page), TamanoPagina: param.int(pageSize) });
  },

  remove(idCupon: number, idUsuario: number): Promise<Row | undefined> {
    return queryOne("SP_Cupones_Eliminar", { IDCupon: param.int(idCupon), IDUsuario: param.int(idUsuario) });
  },
};
