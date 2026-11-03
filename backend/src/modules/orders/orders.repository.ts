import { execute, param, queryOne, queryRows, type Row } from "../../database/procedures.js";
import type { Pagination } from "../../shared/pagination.js";

export interface OrderFilters extends Pagination {
  idEstado: number | undefined;
  idCliente: number | undefined;
  desde: Date | undefined;
  hasta: Date | undefined;
  orden: string;
  direccion: string;
}

export interface Requester {
  id: number;
  esStaff: boolean;
}

export const ordersRepository = {
  list(requester: Requester, filters: OrderFilters): Promise<Row[]> {
    return queryRows("SP_Pedidos_Listar", {
      IDUsuarioSolicitante: param.int(requester.id),
      EsStaff: param.bit(requester.esStaff),
      IDEstadoPedido: param.tinyInt(filters.idEstado),
      IDCliente: param.int(filters.idCliente),
      Desde: param.date(filters.desde),
      Hasta: param.date(filters.hasta),
      Orden: param.text(filters.orden, 10),
      Direccion: param.text(filters.direccion, 4),
      Pagina: param.int(filters.page),
      TamanoPagina: param.int(filters.pageSize),
    });
  },

  async get(idPedido: number, requester: Requester) {
    const [header, lines, history, returns] = await execute("SP_Pedidos_Obtener", {
      IDPedido: param.int(idPedido),
      IDUsuarioSolicitante: param.int(requester.id),
      EsStaff: param.bit(requester.esStaff),
    });
    return { ...header?.[0], detalle: lines ?? [], historial: history ?? [], devoluciones: returns ?? [] };
  },

  async advance(idPedido: number, idEstadoNuevo: number, idUsuario: number): Promise<void> {
    await execute("SP_Pedidos_AvanzarEstado", {
      IDPedido: param.int(idPedido),
      IDEstadoNuevo: param.tinyInt(idEstadoNuevo),
      IDUsuario: param.int(idUsuario),
    });
  },

  async cancel(idPedido: number, requester: Requester): Promise<void> {
    await execute("SP_Pedidos_Cancelar", {
      IDPedido: param.int(idPedido),
      IDUsuario: param.int(requester.id),
      EsStaff: param.bit(requester.esStaff),
    });
  },

  registerReturn(
    idPedido: number,
    input: { motivo: string; lineas: { idPedidoDetalle: number; cantidad: number }[] },
    idUsuario: number,
  ): Promise<Row | undefined> {
    return queryOne("SP_Pedidos_Devolver", {
      IDPedido: param.int(idPedido),
      IDUsuario: param.int(idUsuario),
      Motivo: param.text(input.motivo, 250),
      LineasJson: param.json(input.lineas),
    });
  },
};
