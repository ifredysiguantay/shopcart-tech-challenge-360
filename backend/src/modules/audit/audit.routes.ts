import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { auditRepository } from "./audit.repository.js";

const auditSchema = paginationSchema.extend({
  modulo: z.enum(["Productos", "Precios", "Existencias", "Cupones", "Pedidos"]).optional(),
});

export const auditRouter = Router();

auditRouter.use(authenticate, authorize(Role.Administrador));

auditRouter.get("/", async (req, res) => {
  const query = auditSchema.parse(req.query);
  res.json(toPage(await auditRepository.list(query.modulo, query), query));
});
