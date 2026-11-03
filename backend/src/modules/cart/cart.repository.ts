import { execute, param, queryOne } from "../../database/procedures.js";

export interface CartIdentity {
  idCarrito: number;
  tokenInvitado: string | null;
}

export const cartRepository = {
  async findOrCreate(idUsuario: number | undefined, tokenInvitado: string | undefined): Promise<CartIdentity> {
    const row = await queryOne("SP_Carritos_ObtenerOCrear", {
      IDUsuario: param.int(idUsuario),
      TokenInvitado: param.guid(tokenInvitado),
    });
    return row as unknown as CartIdentity;
  },

  async detail(idCarrito: number) {
    const [items, totals] = await execute("SP_Carritos_Detalle", { IDCarrito: param.int(idCarrito) });
    return { items: items ?? [], ...totals?.[0] };
  },

  async addItem(idCarrito: number, idVariante: number, cantidad: number): Promise<void> {
    await execute("SP_Carritos_AgregarItem", {
      IDCarrito: param.int(idCarrito),
      IDVariante: param.int(idVariante),
      Cantidad: param.int(cantidad),
    });
  },

  async updateItem(idCarrito: number, idVariante: number, cantidad: number): Promise<void> {
    await execute("SP_Carritos_ActualizarItem", {
      IDCarrito: param.int(idCarrito),
      IDVariante: param.int(idVariante),
      Cantidad: param.int(cantidad),
    });
  },

  async removeItem(idCarrito: number, idVariante: number): Promise<void> {
    await execute("SP_Carritos_EliminarItem", { IDCarrito: param.int(idCarrito), IDVariante: param.int(idVariante) });
  },

  async applyCoupon(idCarrito: number, idUsuario: number, codigo: string): Promise<void> {
    await execute("SP_Carritos_AplicarCupon", {
      IDCarrito: param.int(idCarrito),
      IDUsuario: param.int(idUsuario),
      Codigo: param.text(codigo, 30),
    });
  },

  async removeCoupon(idCarrito: number): Promise<void> {
    await execute("SP_Carritos_QuitarCupon", { IDCarrito: param.int(idCarrito) });
  },

  async mergeGuestCart(idUsuario: number, tokenInvitado: string): Promise<void> {
    if (!/^[0-9a-f-]{36}$/i.test(tokenInvitado)) return;
    await execute("SP_Carritos_Fusionar", { IDUsuario: param.int(idUsuario), TokenInvitado: param.guid(tokenInvitado) });
  },
};
