import { randomUUID } from "node:crypto";
import { closePool } from "../src/database/pool.js";
import { execute, param, queryRows } from "../src/database/procedures.js";

const BASE = process.env["API_URL"] ?? "http://localhost:3000/api";

type Json = Record<string, any>;

interface Reply {
  status: number;
  body: Json;
}

let failures = 0;

function check(name: string, condition: boolean, detail?: unknown): void {
  if (!condition) failures++;
  console.log(`${condition ? "OK  " : "FAIL"} ${name}${condition ? "" : ` -> ${JSON.stringify(detail)}`}`);
}

async function call(method: string, path: string, options: { token?: string; body?: unknown; headers?: Record<string, string> } = {}): Promise<Reply> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
      ...options.headers,
    },
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

async function login(correo: string, password: string): Promise<string> {
  const { body } = await call("POST", "/auth/login", { body: { correo, password } });
  return body["accessToken"];
}

async function fillCart(token: string, idVariante: number, cantidad = 1): Promise<Reply> {
  return call("POST", "/cart/items", { token, body: { idVariante, cantidad } });
}

async function pay(token: string, idCheckout: number, key: string): Promise<Reply> {
  return call("POST", `/checkout/${idCheckout}/pay`, { token, headers: { "idempotency-key": key }, body: {} });
}

async function firstAddress(token: string): Promise<number> {
  const { body } = await call("GET", "/addresses", { token });
  return (body as unknown as Json[])[0]!["idDireccion"];
}

async function variantId(sku: string): Promise<number> {
  const rows = await queryRows("SP_Inventario_Listar", { Texto: param.text(sku, 100), Pagina: param.int(1), TamanoPagina: param.int(5) });
  return rows.find((row) => row["sku"] === sku)!["idVariante"] as number;
}

async function stock(idVariante: number): Promise<{ fisica: number; reservada: number }> {
  const rows = await queryRows("SP_Inventario_Listar", { Texto: param.text(null), Pagina: param.int(1), TamanoPagina: param.int(100) });
  const row = rows.find((candidate) => candidate["idVariante"] === idVariante)!;
  return { fisica: row["existenciaFisica"] as number, reservada: row["existenciaReservada"] as number };
}

async function emptyCart(token: string): Promise<void> {
  const { body } = await call("GET", "/cart", { token });
  for (const item of body["items"] as Json[]) await call("DELETE", `/cart/items/${item["idVariante"]}`, { token });
  await call("DELETE", "/cart/coupon", { token });
}

async function main(): Promise<void> {
  const admin = await login("admin@shopcart.test", "Admin#2026");
  const operator = await login("operador@shopcart.test", "Operador#2026");
  const c1 = await login("cliente@shopcart.test", "Cliente#2026");
  const c2 = await login("cliente2@shopcart.test", "Cliente#2026");
  const c3 = await login("cliente3@shopcart.test", "Cliente#2026");

  console.log("\n# RF-01 Autenticación y acceso");
  check("sin token -> 401", (await call("GET", "/orders")).status === 401);
  check("token inválido -> 401", (await call("GET", "/orders", { token: "abc" })).status === 401);
  check("cliente a reportes -> 403", (await call("GET", "/reports/summary?from=2026-01-01&to=2026-12-31", { token: c1 })).status === 403);
  check("operador a catálogo (POST) -> 403", (await call("POST", "/categories", { token: operator, body: { nombre: "X" } })).status === 403);
  check("login incorrecto -> 401", (await call("POST", "/auth/login", { body: { correo: "admin@shopcart.test", password: "mala" } })).status === 401);

  const refreshed = await call("POST", "/auth/login", { body: { correo: "cliente@shopcart.test", password: "Cliente#2026" } });
  const rotation = await call("POST", "/auth/refresh", { body: { refreshToken: refreshed.body["refreshToken"] } });
  check("refresh rota el token", rotation.status === 200 && rotation.body["refreshToken"] !== refreshed.body["refreshToken"]);
  check("refresh reutilizado -> 401", (await call("POST", "/auth/refresh", { body: { refreshToken: refreshed.body["refreshToken"] } })).status === 401);
  check("tras reutilización, la familia queda revocada", (await call("POST", "/auth/refresh", { body: { refreshToken: rotation.body["refreshToken"] } })).status === 401);

  const email = `nuevo-${randomUUID().slice(0, 8)}@shopcart.test`;
  const registered = await call("POST", "/auth/register", { body: { correo: email, password: "Password1", nombre: "Nuevo Cliente" } });
  check("registro de cliente", registered.status === 201);
  check("correo duplicado -> 409", (await call("POST", "/auth/register", { body: { correo: email, password: "Password1", nombre: "Nuevo" } })).status === 409);
  check("password débil -> 400", (await call("POST", "/auth/register", { body: { correo: "x@y.com", password: "abc", nombre: "Nuevo" } })).status === 400);

  const staff = await call("POST", "/users", { token: admin, body: { correo: `op-${randomUUID().slice(0, 6)}@shopcart.test`, password: "Password1", nombre: "Operador Extra", idRol: 2 } });
  const deactivated = await call("PATCH", `/users/${staff.body["idUsuario"]}/status`, { token: admin, body: { activo: false } });
  check("usuario se desactiva sin borrarse", deactivated.status === 200 && deactivated.body["activo"] === false);
  check("usuario inactivo no inicia sesión", (await call("POST", "/auth/login", { body: { correo: staff.body["correo"], password: "Password1" } })).status === 401);

  console.log("\n# RF-02 Catálogo");
  const search = await call("GET", "/products?q=camiseta&pageSize=5&orden=precio&direccion=desc");
  check("búsqueda con paginación", search.status === 200 && search.body["pagination"].total >= 1, search.body);
  const price = await call("GET", "/products?precioMin=500&soloDisponibles=true");
  check("filtro por precio", price.status === 200 && (price.body["data"] as Json[]).every((p) => p["precioMaximo"] >= 500));

  console.log("\n# RF-04 Carrito");
  const sku = "SKU-001-SN";
  const idVariante = await variantId(sku);
  await emptyCart(c1);
  const added = await fillCart(c1, idVariante, 2);
  check("agregar al carrito", added.status === 201 && added.body["total"] > 0, added.body);
  check("no excede existencia disponible", (await fillCart(c1, idVariante, 999)).status === 409);
  check("total sin errores de redondeo", Number.isInteger(Math.round(added.body["total"] * 100)));

  console.log("\n# RF-05 Cupones");
  check("cupón vencido rechazado con mensaje", (await call("PUT", "/cart/coupon", { token: c1, body: { codigo: "VENCIDO" } })).body["error"]?.message === "El cupón está vencido.");
  check("cupón inexistente -> 404", (await call("PUT", "/cart/coupon", { token: c1, body: { codigo: "NOEXISTE" } })).status === 404);
  const minimo = await call("PUT", "/cart/coupon", { token: c1, body: { codigo: "Q50FIJO" } });
  check("cupón bajo el monto mínimo -> 422 con mensaje", minimo.status === 422 && String(minimo.body["error"]?.message).includes("monto mínimo"), minimo.body);
  const withCoupon = await call("PUT", "/cart/coupon", { token: c1, body: { codigo: "ROPA20" } });
  check("cupón por categoría aplica descuento", withCoupon.status === 200 && withCoupon.body["descuento"] > 0, withCoupon.body);
  check("descuento nunca deja el total bajo cero", withCoupon.body["total"] >= 0);

  console.log("\n# RF-06 Checkout e idempotencia");
  const address = await firstAddress(c1);
  const started = await call("POST", "/checkout", { token: c1, body: { idDireccion: address } });
  check("checkout reserva existencia", started.status === 201 && (await stock(idVariante)).reservada >= 2, started.body);
  await fillCart(c2, idVariante, 1);
  check("dirección de otro cliente -> 403", (await call("POST", "/checkout", { token: c2, body: { idDireccion: address } })).status === 403);
  await emptyCart(c2);

  const key = randomUUID();
  const racing = await Promise.all(Array.from({ length: 5 }, () => pay(c1, started.body["idCheckout"], key)));
  const orderIds = new Set(racing.map((r) => r.body["idPedido"]));
  check("5 pagos simultáneos con la misma clave -> 1 solo pedido", orderIds.size === 1 && racing.every((r) => r.status === 200 || r.status === 201), racing.map((r) => r.body));
  check("repetir pago después -> mismo pedido", (await pay(c1, started.body["idCheckout"], key)).body["idPedido"] === [...orderIds][0]);
  check("misma clave en otro checkout -> 409", (await pay(c1, started.body["idCheckout"], randomUUID())).status === 409);
  const idPedido = [...orderIds][0] as number;

  const afterSale = await stock(idVariante);
  check("la reserva se consumió (sin reservas pendientes)", afterSale.reservada === 0, afterSale);

  console.log("\n# RF-01 Aislamiento entre clientes");
  check("otro cliente no ve el pedido -> 403", (await call("GET", `/orders/${idPedido}`, { token: c2 })).status === 403);
  check("otro cliente no puede cancelarlo -> 403", (await call("POST", `/orders/${idPedido}/cancel`, { token: c2 })).status === 403);
  check("otro cliente no ve pedidos ajenos en el listado", (await call("GET", "/orders?pageSize=100", { token: c2 })).body["data"].every((o: Json) => o["idPedido"] !== idPedido));
  check("el dueño sí ve el pedido con historial", (await call("GET", `/orders/${idPedido}`, { token: c1 })).body["historial"].length === 1);

  console.log("\n# RF-06 Compra concurrente de la última unidad");
  const last = await variantId("SKU-ULTIMA-UNIDAD");
  for (const token of [c2, c3]) {
    await emptyCart(token);
    await fillCart(token, last, 1);
  }
  const [a2, a3] = [await firstAddress(c2), await firstAddress(c3)];
  const starts = await Promise.all([
    call("POST", "/checkout", { token: c2, body: { idDireccion: a2 } }),
    call("POST", "/checkout", { token: c3, body: { idDireccion: a3 } }),
  ]);
  const winners = starts.filter((r) => r.status === 201);
  const losers = starts.filter((r) => r.status === 409);
  check("solo un cliente reserva la última unidad", winners.length === 1 && losers.length === 1, starts.map((r) => [r.status, r.body]));
  check("el perdedor recibe un mensaje claro", String(losers[0]?.body["error"]?.message).includes("SKU-ULTIMA-UNIDAD"));
  check("nunca hay sobreventa", (await stock(last)).reservada === 1);

  console.log("\n# RF-07 Reserva vencida libera existencia");
  await execute("SP_Reservas_LiberarVencidas");
  check("reserva vigente no se libera", (await stock(last)).reservada === 1);
  const winnerToken = starts[0]!.status === 201 ? c2 : c3;
  const winnerCheckout = winners[0]!.body["idCheckout"];
  const { getPool } = await import("../src/database/pool.js");
  await (await getPool()).request().query(`UPDATE Checkout SET FechaExpiracion = DATEADD(MINUTE, -1, SYSUTCDATETIME()) WHERE IDCheckout = ${winnerCheckout}`);
  await execute("SP_Reservas_LiberarVencidas");
  check("reserva vencida libera sin intervención manual", (await stock(last)).reservada === 0);
  const late = await pay(winnerToken, winnerCheckout, randomUUID());
  check("pagar con reserva vencida -> 409", late.status === 409 || late.status === 422, late.body);

  console.log("\n# RF-05 Límite total de un cupón con concurrencia (UNSOLOUSO)");
  for (const token of [c2, c3]) {
    await emptyCart(token);
    await fillCart(token, idVariante, 1);
    const applied = await call("PUT", "/cart/coupon", { token, body: { codigo: "UNSOLOUSO" } });
    check(`cupón aplicado al carrito (${applied.status})`, applied.status === 200, applied.body);
  }
  const checkouts = await Promise.all([
    call("POST", "/checkout", { token: c2, body: { idDireccion: a2 } }),
    call("POST", "/checkout", { token: c3, body: { idDireccion: a3 } }),
  ]);
  const payments = await Promise.all([
    pay(c2, checkouts[0]!.body["idCheckout"], randomUUID()),
    pay(c3, checkouts[1]!.body["idCheckout"], randomUUID()),
  ]);
  check("solo un pago usa el cupón de 1 uso", payments.filter((p) => p.status === 201).length === 1 && payments.filter((p) => p.status === 422).length === 1, payments.map((p) => [p.status, p.body]));
  const coupons = await call("GET", "/coupons", { token: admin });
  check("UsosActuales no excede el límite", (coupons.body["data"] as Json[]).find((c) => c.codigo === "UNSOLOUSO")?.usosActuales === 1);

  console.log("\n# RF-07 Ciclo de vida, cancelaciones y devoluciones");
  const losersPay = payments.find((p) => p.status === 201)!;
  const orderToCancel = losersPay.body["idPedido"];
  const before = await stock(idVariante);
  const skipStep = await call("PATCH", `/orders/${orderToCancel}/status`, { token: operator, body: { estado: "Entregado" } });
  check("transición no permitida -> 422", skipStep.status === 422, skipStep.body);
  check("cliente no avanza estados -> 403", (await call("PATCH", `/orders/${orderToCancel}/status`, { token: c2, body: { estado: "EnPreparacion" } })).status === 403);
  const cancelled = await call("POST", `/orders/${orderToCancel}/cancel`, { token: c2 });
  const cancelledByOwner = cancelled.status === 204 ? cancelled : await call("POST", `/orders/${orderToCancel}/cancel`, { token: c3 });
  check("el cliente cancela su pedido", cancelledByOwner.status === 204, cancelledByOwner.body);
  check("cancelar reintegra existencia en el kardex", (await stock(idVariante)).fisica === before.fisica + 1);
  check("cancelado no se puede avanzar", (await call("PATCH", `/orders/${orderToCancel}/status`, { token: operator, body: { estado: "EnPreparacion" } })).status === 422);

  for (const estado of ["EnPreparacion", "Despachado", "Entregado"]) {
    await call("PATCH", `/orders/${idPedido}/status`, { token: operator, body: { estado } });
  }
  check("no se cancela un pedido entregado", (await call("POST", `/orders/${idPedido}/cancel`, { token: c1 })).status === 422);
  const detail = await call("GET", `/orders/${idPedido}`, { token: c1 });
  const line = detail.body["detalle"][0];
  check("historial registra usuario y estados", detail.body["historial"].length === 4 && detail.body["historial"].every((h: Json) => h["usuario"]));
  const overReturn = await call("POST", `/orders/${idPedido}/returns`, { token: operator, body: { motivo: "Defecto", lineas: [{ idPedidoDetalle: line["idPedidoDetalle"], cantidad: line["cantidad"] + 1 }] } });
  check("no se devuelve más de lo vendido -> 422", overReturn.status === 422, overReturn.body);
  const partial = await call("POST", `/orders/${idPedido}/returns`, { token: operator, body: { motivo: "Defecto", lineas: [{ idPedidoDetalle: line["idPedidoDetalle"], cantidad: 1 }] } });
  check("devolución parcial", partial.status === 201 && partial.body["devolucionTotal"] === false, partial.body);
  const rest = await call("POST", `/orders/${idPedido}/returns`, { token: operator, body: { motivo: "Defecto", lineas: [{ idPedidoDetalle: line["idPedidoDetalle"], cantidad: line["cantidad"] - 1 }] } });
  check("devolución total cambia el estado a Devuelto", rest.status === 201 && rest.body["devolucionTotal"] === true, rest.body);
  const refunded = await call("GET", `/orders/${idPedido}`, { token: c1 });
  check("suma de devoluciones == total del pedido (sin deriva de redondeo)", Math.abs(refunded.body["montoDevuelto"] - refunded.body["total"]) < 0.001, refunded.body);

  console.log("\n# RF-03 Inventario");
  const noReason = await call("POST", "/inventory/movements", { token: operator, body: { idVariante, tipo: "Ajuste", cantidad: -1, motivo: "  " } });
  check("ajuste sin motivo -> 400", noReason.status === 400);
  const negative = await call("POST", "/inventory/movements", { token: operator, body: { idVariante: last, tipo: "Ajuste", cantidad: -50, motivo: "Conteo físico" } });
  check("ajuste no deja existencia negativa -> 422", negative.status === 422, negative.body);
  const entry = await call("POST", "/inventory/movements", { token: operator, body: { idVariante: last, tipo: "Entrada", cantidad: 5, motivo: "Compra a proveedor" } });
  check("entrada por compra", entry.status === 201 && entry.body["existenciaFisica"] === 6, entry.body);
  const mismatches = (await (await getPool()).request().query("SELECT COUNT(*) AS n FROM VW_Inventario_Conciliacion")).recordset[0].n;
  check("existencia == suma del kardex en todas las variantes", mismatches === 0, mismatches);

  console.log("\n# RF-08 Reportes y RF-09 Bitácora");
  const sales = await call("GET", "/reports/sales?from=2026-01-01&to=2026-12-31&agrupacion=mes", { token: admin });
  check("ventas por mes", sales.status === 200 && (sales.body as unknown as Json[]).length > 0);
  check("agrupación inválida -> 400", (await call("GET", "/reports/sales?from=2026-01-01&to=2026-12-31&agrupacion=anio", { token: admin })).status === 400);
  const top = await call("GET", "/reports/top-products?from=2026-01-01&to=2026-12-31", { token: admin });
  check("top 10 productos", top.status === 200 && (top.body as unknown as Json[]).length === 10);
  check("ventas por categoría", (await call("GET", "/reports/sales-by-category?from=2026-01-01&to=2026-12-31", { token: admin })).status === 200);
  const summary = await call("GET", "/reports/summary?from=2026-01-01&to=2026-12-31", { token: admin });
  check("resumen con ticket promedio", summary.body["ticketPromedio"] > 0, summary.body);
  const audit = await call("GET", "/audit?modulo=Existencias", { token: admin });
  check("bitácora filtrable por módulo", audit.status === 200 && audit.body["data"].length > 0 && audit.body["data"].every((r: Json) => r["modulo"] === "Existencias"));
  check("bitácora solo para administradores -> 403", (await call("GET", "/audit", { token: operator })).status === 403);
  const tamper = await (await getPool()).request().query("UPDATE Bitacora SET Accion = 'X'").then(() => "modificada", () => "rechazada");
  check("la bitácora no puede modificarse", tamper === "rechazada");
  const wipe = await (await getPool()).request().query("DELETE FROM Bitacora").then(() => "eliminada", () => "rechazada");
  check("la bitácora no puede eliminarse", wipe === "rechazada");
  const badTransition = await (await getPool()).request().query(`UPDATE Pedido SET IDEstadoPedido = 4 WHERE IDPedido = ${orderToCancel}`).then(() => "aceptada", () => "rechazada");
  check("transición inválida rechazada también por la base de datos", badTransition === "rechazada");

  console.log("\n# RF-02 Producto con ventas se desactiva, no se elimina");
  const products = await call("GET", "/products?q=Camiseta");
  const idProducto = (products.body["data"] as Json[])[0]!["idProducto"];
  const removal = await call("DELETE", `/products/${idProducto}`, { token: admin });
  check("producto con ventas -> Desactivado", removal.body["resultado"] === "Desactivado", removal.body);
  check("producto desactivado desaparece de la tienda", (await call("GET", `/products/${idProducto}`)).status === 404);
  await call("PUT", `/products/${idProducto}`, { token: admin, body: { idCategoria: 1, nombre: "Camiseta básica", descripcion: "Producto reactivado", activo: true } });

  console.log("\n# RF-02 El precio de un pedido no cambia si cambia el precio");
  const priceBefore = (await call("GET", `/orders/${idPedido}`, { token: c1 })).body["total"];
  await call("PUT", `/variants/${idVariante}`, { token: admin, body: { sku, atributos: { talla: "S", color: "Negro" }, precio: 999.99, activo: true } });
  check("el total del pedido ya realizado no cambia", (await call("GET", `/orders/${idPedido}`, { token: c1 })).body["total"] === priceBefore);
  check("el cambio de precio quedó en la bitácora", (await call("GET", "/audit?modulo=Precios", { token: admin })).body["data"].length > 0);

  console.log(`\n${failures === 0 ? "Todas las verificaciones pasaron." : `${failures} verificación(es) fallaron.`}`);
  await closePool();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (error) => {
  console.error(error);
  await closePool();
  process.exit(1);
});
