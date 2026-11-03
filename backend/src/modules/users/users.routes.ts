import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize, requireUser } from "../../shared/middleware.js";
import { paginationSchema } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { idParam } from "../../shared/schemas.js";
import { usersService } from "./users.service.js";

const createUserSchema = z.object({
  correo: z.email().max(256).transform((value) => value.toLowerCase()),
  password: z.string().min(8).max(72),
  nombre: z.string().trim().min(2).max(100),
  idRol: z.union([z.literal(Role.Cliente), z.literal(Role.Operador), z.literal(Role.Administrador)]),
});

const statusSchema = z.object({ activo: z.boolean() });

export const usersRouter = Router();

usersRouter.use(authenticate, authorize(Role.Administrador));

usersRouter.get("/", async (req, res) => {
  res.json(await usersService.list(paginationSchema.parse(req.query)));
});

usersRouter.post("/", async (req, res) => {
  res.status(201).json(await usersService.create(createUserSchema.parse(req.body)));
});

usersRouter.patch("/:id/status", async (req, res) => {
  const { activo } = statusSchema.parse(req.body);
  res.json(await usersService.changeStatus(idParam.parse(req.params["id"]), activo, requireUser(req).id));
});
