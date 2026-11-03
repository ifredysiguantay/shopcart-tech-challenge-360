import { Router } from "express";
import { z } from "zod";
import { badRequest } from "../../shared/errors.js";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { Role } from "../../shared/roles.js";
import { idParam } from "../../shared/schemas.js";
import { checkoutRepository } from "./checkout.repository.js";

const startSchema = z.object({ idDireccion: z.number().int().positive() });
const paySchema = z.object({ metodoPago: z.enum(["Tarjeta", "Efectivo", "Transferencia"]).default("Tarjeta") });
const idempotencyKeySchema = z.string().trim().min(8).max(100);

export const checkoutRouter = Router();

checkoutRouter.use(authenticate, authorize(Role.Cliente));

checkoutRouter.post("/", async (req, res) => {
  const { idDireccion } = startSchema.parse(req.body);
  res.status(201).json(await checkoutRepository.start(requireUser(req).id, idDireccion));
});

checkoutRouter.post("/:id/pay", async (req, res) => {
  const key = idempotencyKeySchema.safeParse(req.header("idempotency-key"));
  if (!key.success) throw badRequest("El encabezado Idempotency-Key es obligatorio (mínimo 8 caracteres).");

  const { metodoPago } = paySchema.parse(req.body ?? {});
  const result = await checkoutRepository.pay(idParam.parse(req.params["id"]), requireUser(req).id, key.data, metodoPago);
  res.status(result?.["repetido"] ? 200 : 201).json(result);
});
