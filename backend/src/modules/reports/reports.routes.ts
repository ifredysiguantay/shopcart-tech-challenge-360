import { Router } from "express";
import { z } from "zod";
import { authenticate, authorize } from "../../shared/middleware.js";
import { paginationSchema, toPage } from "../../shared/pagination.js";
import { Role } from "../../shared/roles.js";
import { dateRangeSchema } from "../../shared/schemas.js";
import { reportsRepository } from "./reports.repository.js";

const MAX_TOP = 10;

const salesSchema = dateRangeSchema.extend({ agrupacion: z.enum(["dia", "semana", "mes"]).default("dia") });
const topSchema = dateRangeSchema.extend({ top: z.coerce.number().int().min(1).max(MAX_TOP).default(MAX_TOP) });

export const reportsRouter = Router();

reportsRouter.use(authenticate, authorize(Role.Administrador));

reportsRouter.get("/summary", async (req, res) => {
  res.json(await reportsRepository.summary(dateRangeSchema.parse(req.query)));
});

reportsRouter.get("/sales", async (req, res) => {
  const { agrupacion, ...range } = salesSchema.parse(req.query);
  res.json(await reportsRepository.salesByPeriod(agrupacion, range));
});

reportsRouter.get("/sales-by-category", async (req, res) => {
  res.json(await reportsRepository.salesByCategory(dateRangeSchema.parse(req.query)));
});

reportsRouter.get("/top-products", async (req, res) => {
  const { top, ...range } = topSchema.parse(req.query);
  res.json(await reportsRepository.topProducts(range, top));
});

reportsRouter.get("/abandoned-carts", async (req, res) => {
  const pagination = paginationSchema.parse(req.query);
  res.json(toPage(await reportsRepository.abandonedCarts(pagination), pagination));
});
