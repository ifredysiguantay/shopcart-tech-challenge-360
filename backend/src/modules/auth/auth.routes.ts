import { Router } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import { authenticate, requireUser } from "../../shared/middleware.js";
import { authService } from "./auth.service.js";

const password = z
  .string()
  .min(8)
  .max(72)
  .regex(/[A-Za-z]/, "Debe incluir letras")
  .regex(/\d/, "Debe incluir números");

const registerSchema = z.object({
  correo: z.email().max(256).transform((value) => value.toLowerCase()),
  password,
  nombre: z.string().trim().min(2).max(100),
});

const loginSchema = z.object({
  correo: z.email().transform((value) => value.toLowerCase()),
  password: z.string().min(1),
});

const refreshSchema = z.object({ refreshToken: z.string().min(1) });

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: { code: "RATE_LIMITED", message: "Demasiados intentos, intenta más tarde." } },
});

export const authRouter = Router();

authRouter.use(authLimiter);

authRouter.post("/register", async (req, res) => {
  res.status(201).json(await authService.register(registerSchema.parse(req.body)));
});

authRouter.post("/login", async (req, res) => {
  const guestCartToken = req.header("x-cart-token") ?? undefined;
  res.json(await authService.login(loginSchema.parse(req.body), guestCartToken));
});

authRouter.post("/refresh", async (req, res) => {
  res.json(await authService.refresh(refreshSchema.parse(req.body).refreshToken));
});

authRouter.post("/logout", async (req, res) => {
  await authService.logout(refreshSchema.parse(req.body).refreshToken);
  res.status(204).end();
});

authRouter.get("/me", authenticate, async (req, res) => {
  res.json(await authService.currentUser(requireUser(req).id));
});
