import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { idParam } from "../../shared/schemas.js";
import { couponsRepository } from "./coupons.repository.js";

const couponSchema = z
  .object({
    tipo: z.enum(["Porcentaje", "MontoFijo"]),
    valor: z.number().positive().multipleOf(0.01),
    fechaInicio: z.coerce.date(),
    fechaFin: z.coerce.date(),
    montoMinimo: z.number().min(0).default(0),
    limiteUsosTotal: z.number().int().positive(),
    limiteUsosPorCliente: z.number().int().positive(),
    idCategoria: z.number().int().positive().optional(),
  })
  .refine((coupon) => coupon.fechaFin > coupon.fechaInicio, { message: "La fecha fin debe ser posterior al inicio", path: ["fechaFin"] })
  .refine((coupon) => coupon.tipo !== "Porcentaje" || coupon.valor <= 100, { message: "El porcentaje no puede exceder 100", path: ["valor"] })
  .refine((coupon) => coupon.limiteUsosPorCliente <= coupon.limiteUsosTotal, {
    message: "El límite por cliente no puede exceder el límite total",
    path: ["limiteUsosPorCliente"],
  });

const createCouponSchema = couponSchema.and(z.object({ codigo: z.string().trim().toUpperCase().regex(/^[A-Z0-9_-]{3,30}$/) }));
const updateCouponSchema = couponSchema.and(z.object({ activo: z.boolean() }));

export const couponsRouter = Router();

couponsRouter.use(authenticate, authorize(Role.Administrador));

couponsRouter.get("/", async (req, res) => {
  const pagination = paginationSchema.parse(req.query);
  res.json(toPage(await couponsRepository.list(pagination), pagination));
});

couponsRouter.post("/", async (req, res) => {
  const { codigo, ...input } = createCouponSchema.parse(req.body);
  res.status(201).json(await couponsRepository.create(codigo, input, requireUser(req).id));
});

couponsRouter.put("/:id", async (req, res) => {
  const input = updateCouponSchema.parse(req.body);
  await couponsRepository.update(idParam.parse(req.params["id"]), input, requireUser(req).id);
  res.status(204).end();
});

couponsRouter.delete("/:id", async (req, res) => {
  res.json(await couponsRepository.remove(idParam.parse(req.params["id"]), requireUser(req).id));
});
