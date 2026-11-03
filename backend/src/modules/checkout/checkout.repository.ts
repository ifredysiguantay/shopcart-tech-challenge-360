import { env } from "../../config/env.js";
import { execute, param, queryOne } from "../../database/procedures.js";

export const checkoutRepository = {
  async start(idUsuario: number, idDireccion: number) {
    const [header, lines] = await execute("SP_Checkout_Iniciar", {
      IDUsuario: param.int(idUsuario),
      IDDireccion: param.int(idDireccion),
      MinutosReserva: param.int(env.RESERVATION_MINUTES),
    });
    return { ...header?.[0], lineas: lines ?? [] };
  },

  pay(idCheckout: number, idUsuario: number, idempotencyKey: string, metodoPago: string) {
    return queryOne("SP_Checkout_Pagar", {
      IDCheckout: param.int(idCheckout),
      IDUsuario: param.int(idUsuario),
      ClaveIdempotencia: param.text(idempotencyKey, 100),
      MetodoPago: param.text(metodoPago, 30),
    });
  },
};
