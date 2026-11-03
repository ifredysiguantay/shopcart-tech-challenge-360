import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role, isStaff } from "../../shared/roles.js";
import { idParam, isoDate, sortDirection } from "../../shared/schemas.js";
import { ordersRepository, type Requester } from "./orders.repository.js";

const OrderState = {
  Pagado: 1,
  EnPreparacion: 2,
  Despachado: 3,
  Entregado: 4,
  Cancelado: 5,
  Devuelto: 6,
} as const;

const stateName = z.enum(["Pagado", "EnPreparacion", "Despachado", "Entregado", "Cancelado", "Devuelto"]);

const listSchema = paginationSchema.extend({
  estado: stateName.optional(),
  cliente: z.coerce.number().int().positive().optional(),
  desde: isoDate.optional(),
  hasta: isoDate.optional(),
  orden: z.enum(["fecha", "total"]).default("fecha"),
  direccion: sortDirection.default("desc"),
});

const advanceSchema = z.object({ estado: stateName });

const returnSchema = z.object({
  motivo: z.string().trim().min(3).max(250),
  lineas: z
    .array(z.object({ idPedidoDetalle: z.number().int().positive(), cantidad: z.number().int().positive() }))
    .min(1),
});

function requesterOf(req: Parameters<typeof requireUser>[0]): Requester {
  const user = requireUser(req);
  return { id: user.id, esStaff: isStaff(user.rol) };
}

export const ordersRouter = Router();

ordersRouter.use(authenticate);

ordersRouter.get("/", async (req, res) => {
  const query = listSchema.parse(req.query);
  const rows = await ordersRepository.list(requesterOf(req), {
    ...query,
    idEstado: query.estado ? OrderState[query.estado] : undefined,
    idCliente: query.cliente,
    desde: query.desde,
    hasta: query.hasta,
  });
  res.json(toPage(rows, query));
});

ordersRouter.get("/:id", async (req, res) => {
  res.json(await ordersRepository.get(idParam.parse(req.params["id"]), requesterOf(req)));
});

ordersRouter.patch("/:id/status", authorize(Role.Operador, Role.Administrador), async (req, res) => {
  const { estado } = advanceSchema.parse(req.body);
  await ordersRepository.advance(idParam.parse(req.params["id"]), OrderState[estado], requireUser(req).id);
  res.status(204).end();
});

ordersRouter.post("/:id/cancel", async (req, res) => {
  await ordersRepository.cancel(idParam.parse(req.params["id"]), requesterOf(req));
  res.status(204).end();
});

ordersRouter.post("/:id/returns", authorize(Role.Operador, Role.Administrador), async (req, res) => {
  const input = returnSchema.parse(req.body);
  res.status(201).json(await ordersRepository.registerReturn(idParam.parse(req.params["id"]), input, requireUser(req).id));
});
