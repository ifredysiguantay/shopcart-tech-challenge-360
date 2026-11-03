import cors from "cors";
import express from "express";
import helmet from "helmet";
import { env } from "./config/env.js";
import { addressesRouter } from "./modules/addresses/addresses.routes.js";
import { auditRouter } from "./modules/audit/audit.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { cartRouter } from "./modules/cart/cart.routes.js";
import { categoriesRouter, productsRouter, variantsRouter } from "./modules/catalog/catalog.routes.js";
import { checkoutRouter } from "./modules/checkout/checkout.routes.js";
import { couponsRouter } from "./modules/coupons/coupons.routes.js";
import { inventoryRouter } from "./modules/inventory/inventory.routes.js";
import { ordersRouter } from "./modules/orders/orders.routes.js";
import { reportsRouter } from "./modules/reports/reports.routes.js";
import { usersRouter } from "./modules/users/users.routes.js";
import { errorHandler, notFoundHandler } from "./shared/middleware.js";

export function createApp(): express.Express {
  const app = express();

  app.disable("x-powered-by");
  app.use(helmet());
  app.use(cors({ origin: env.corsOrigins, exposedHeaders: ["X-Cart-Token"] }));
  app.use(express.json({ limit: "100kb" }));

  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  app.use("/api/auth", authRouter);
  app.use("/api/users", usersRouter);
  app.use("/api/addresses", addressesRouter);
  app.use("/api/categories", categoriesRouter);
  app.use("/api/products", productsRouter);
  app.use("/api/variants", variantsRouter);
  app.use("/api/inventory", inventoryRouter);
  app.use("/api/cart", cartRouter);
  app.use("/api/coupons", couponsRouter);
  app.use("/api/checkout", checkoutRouter);
  app.use("/api/orders", ordersRouter);
  app.use("/api/reports", reportsRouter);
  app.use("/api/audit", auditRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
