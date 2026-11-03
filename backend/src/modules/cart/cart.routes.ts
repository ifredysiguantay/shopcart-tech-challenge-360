import { Router, type Request, type Response } from "express";
import { z } from "zod";
import { badRequest } from "../../shared/errors.js";
import { authenticate, optionalAuthenticate, requireUser } from "../../shared/middleware.js";
import { idParam } from "../../shared/schemas.js";
import { cartRepository } from "./cart.repository.js";

const itemSchema = z.object({
  idVariante: z.number().int().positive(),
  cantidad: z.number().int().positive().max(999),
});

const quantitySchema = z.object({ cantidad: z.number().int().positive().max(999) });
const couponSchema = z.object({ codigo: z.string().trim().min(1).max(30) });
const guestToken = z.uuid();

async function resolveCart(req: Request) {
  if (req.user) return cartRepository.findOrCreate(req.user.id, undefined);

  const header = req.header("x-cart-token");
  const token = header ? guestToken.safeParse(header) : undefined;
  if (token && !token.success) throw badRequest("El token de carrito es inválido.");
  return cartRepository.findOrCreate(undefined, token?.data);
}

async function respondWithCart(req: Request, res: Response, status = 200): Promise<void> {
  const cart = await resolveCart(req);
  const detail = await cartRepository.detail(cart.idCarrito);
  res.status(status).json({ ...detail, ...(cart.tokenInvitado ? { cartToken: cart.tokenInvitado } : {}) });
}

export const cartRouter = Router();

cartRouter.use(optionalAuthenticate);

cartRouter.get("/", async (req, res) => {
  await respondWithCart(req, res);
});

cartRouter.post("/items", async (req, res) => {
  const { idVariante, cantidad } = itemSchema.parse(req.body);
  const cart = await resolveCart(req);
  await cartRepository.addItem(cart.idCarrito, idVariante, cantidad);
  await respondWithCart(req, res, 201);
});

cartRouter.patch("/items/:idVariante", async (req, res) => {
  const { cantidad } = quantitySchema.parse(req.body);
  const cart = await resolveCart(req);
  await cartRepository.updateItem(cart.idCarrito, idParam.parse(req.params["idVariante"]), cantidad);
  await respondWithCart(req, res);
});

cartRouter.delete("/items/:idVariante", async (req, res) => {
  const cart = await resolveCart(req);
  await cartRepository.removeItem(cart.idCarrito, idParam.parse(req.params["idVariante"]));
  await respondWithCart(req, res);
});

cartRouter.put("/coupon", authenticate, async (req, res) => {
  const { codigo } = couponSchema.parse(req.body);
  const cart = await resolveCart(req);
  await cartRepository.applyCoupon(cart.idCarrito, requireUser(req).id, codigo);
  await respondWithCart(req, res);
});

cartRouter.delete("/coupon", authenticate, async (req, res) => {
  const cart = await resolveCart(req);
  await cartRepository.removeCoupon(cart.idCarrito);
  await respondWithCart(req, res);
});
