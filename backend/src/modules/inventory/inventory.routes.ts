import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { idParam } from "../../shared/schemas.js";
import { inventoryRepository } from "./inventory.repository.js";

const movementSchema = z.object({
  idVariante: z.number().int().positive(),
  tipo: z.enum(["Entrada", "Ajuste"]),
  cantidad: z.number().int().refine((value) => value !== 0, "La cantidad no puede ser cero"),
  motivo: z.string().trim().min(3).max(250),
});

const listSchema = paginationSchema.extend({ q: z.string().trim().max(100).optional() });

export const inventoryRouter = Router();

inventoryRouter.use(authenticate, authorize(Role.Operador, Role.Administrador));

inventoryRouter.get("/", async (req, res) => {
  const query = listSchema.parse(req.query);
  res.json(toPage(await inventoryRepository.list(query.q, query), query));
});

inventoryRouter.get("/variants/:id/kardex", async (req, res) => {
  const pagination = paginationSchema.parse(req.query);
  res.json(toPage(await inventoryRepository.kardex(idParam.parse(req.params["id"]), pagination), pagination));
});

inventoryRouter.post("/movements", async (req, res) => {
  res.status(201).json(await inventoryRepository.registerMovement(movementSchema.parse(req.body), requireUser(req).id));
});
