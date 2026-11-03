import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { Role } from "../../shared/roles.js";
import { idParam } from "../../shared/schemas.js";
import { addressesRepository } from "./addresses.repository.js";

const addressSchema = z.object({
  alias: z.string().trim().min(1).max(50),
  direccion: z.string().trim().min(5).max(250),
  ciudad: z.string().trim().min(2).max(100),
  departamento: z.string().trim().min(2).max(100),
  telefono: z.string().trim().regex(/^[0-9+\-\s]{8,20}$/, "Teléfono inválido"),
});

export const addressesRouter = Router();

addressesRouter.use(authenticate, authorize(Role.Cliente));

addressesRouter.get("/", async (req, res) => {
  res.json(await addressesRepository.list(requireUser(req).id));
});

addressesRouter.post("/", async (req, res) => {
  res.status(201).json(await addressesRepository.create(requireUser(req).id, addressSchema.parse(req.body)));
});

addressesRouter.put("/:id", async (req, res) => {
  const input = addressSchema.parse(req.body);
  res.json(await addressesRepository.update(idParam.parse(req.params["id"]), requireUser(req).id, input));
});

addressesRouter.delete("/:id", async (req, res) => {
  await addressesRepository.deactivate(idParam.parse(req.params["id"]), requireUser(req).id);
  res.status(204).end();
});
