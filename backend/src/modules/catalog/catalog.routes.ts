import { Router, type Request } from "express";
import { z } from "zod";
import { authenticate, authorize, optionalAuthenticate, requireUser } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { idParam, moneyAmount, sortDirection } from "../../shared/schemas.js";
import { catalogRepository } from "./catalog.repository.js";

const booleanQuery = z.enum(["true", "false"]).transform((value) => value === "true");

const categorySchema = z.object({
  nombre: z.string().trim().min(2).max(100),
  descripcion: z.string().trim().max(500).optional(),
});

const categoryUpdateSchema = categorySchema.extend({ activo: z.boolean() });

const variantSchema = z.object({
  sku: z.string().trim().min(1).max(50),
  atributos: z.record(z.string(), z.string()).default({}),
  precio: moneyAmount,
});

const newVariantSchema = variantSchema.extend({ existenciaInicial: z.number().int().min(0).default(0) });

const productSchema = z.object({
  idCategoria: z.number().int().positive(),
  nombre: z.string().trim().min(2).max(150),
  descripcion: z.string().trim().max(2000).default(""),
  imagenes: z.array(z.url().max(500)).max(10).optional(),
});

const createProductSchema = productSchema.extend({ variantes: z.array(newVariantSchema).min(1) });
const updateProductSchema = productSchema.extend({ activo: z.boolean() });
const updateVariantSchema = variantSchema.extend({ activo: z.boolean() });

const searchSchema = paginationSchema.extend({
  q: z.string().trim().max(100).optional(),
  categoria: z.coerce.number().int().positive().optional(),
  precioMin: z.coerce.number().min(0).optional(),
  precioMax: z.coerce.number().min(0).optional(),
  soloDisponibles: booleanQuery.default(false),
  incluirInactivos: booleanQuery.default(false),
  orden: z.enum(["nombre", "precio"]).default("nombre"),
  direccion: sortDirection.default("asc"),
});

const isAdmin = (req: Request): boolean => req.user?.rol === Role.Administrador;
const adminOnly = [authenticate, authorize(Role.Administrador)];

export const categoriesRouter = Router();

categoriesRouter.get("/", optionalAuthenticate, async (req, res) => {
  const includeInactive = booleanQuery.default(false).parse(req.query["incluirInactivas"]) && isAdmin(req);
  res.json(await catalogRepository.listCategories(includeInactive));
});

categoriesRouter.post("/", ...adminOnly, async (req, res) => {
  res.status(201).json(await catalogRepository.createCategory(categorySchema.parse(req.body)));
});

categoriesRouter.put("/:id", ...adminOnly, async (req, res) => {
  const input = categoryUpdateSchema.parse(req.body);
  res.json(await catalogRepository.updateCategory(idParam.parse(req.params["id"]), input));
});

categoriesRouter.delete("/:id", ...adminOnly, async (req, res) => {
  await catalogRepository.deleteCategory(idParam.parse(req.params["id"]));
  res.status(204).end();
});

export const productsRouter = Router();

productsRouter.get("/", optionalAuthenticate, async (req, res) => {
  const query = searchSchema.parse(req.query);
  const rows = await catalogRepository.searchProducts({
    texto: query.q,
    idCategoria: query.categoria,
    precioMinimo: query.precioMin,
    precioMaximo: query.precioMax,
    soloDisponibles: query.soloDisponibles,
    incluirInactivos: query.incluirInactivos && isAdmin(req),
    orden: query.orden,
    direccion: query.direccion,
    page: query.page,
    pageSize: query.pageSize,
  });
  res.json(toPage(rows, query));
});

productsRouter.get("/:id", optionalAuthenticate, async (req, res) => {
  res.json(await catalogRepository.getProduct(idParam.parse(req.params["id"]), isAdmin(req)));
});

productsRouter.post("/", ...adminOnly, async (req, res) => {
  const input = createProductSchema.parse(req.body);
  res.status(201).json(await catalogRepository.createProduct(input, requireUser(req).id));
});

productsRouter.put("/:id", ...adminOnly, async (req, res) => {
  const input = updateProductSchema.parse(req.body);
  await catalogRepository.updateProduct(idParam.parse(req.params["id"]), input, requireUser(req).id);
  res.status(204).end();
});

productsRouter.delete("/:id", ...adminOnly, async (req, res) => {
  res.json(await catalogRepository.deleteProduct(idParam.parse(req.params["id"]), requireUser(req).id));
});

productsRouter.post("/:id/variants", ...adminOnly, async (req, res) => {
  const input = newVariantSchema.parse(req.body);
  res.status(201).json(await catalogRepository.createVariant(idParam.parse(req.params["id"]), input, requireUser(req).id));
});

export const variantsRouter = Router();

variantsRouter.put("/:id", ...adminOnly, async (req, res) => {
  const input = updateVariantSchema.parse(req.body);
  await catalogRepository.updateVariant(idParam.parse(req.params["id"]), input, requireUser(req).id);
  res.status(204).end();
});
