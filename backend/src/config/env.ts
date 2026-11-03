import "dotenv/config";
import { z } from "zod";

const booleanFromString = z.enum(["true", "false"]).default("false").transform((value) => value === "true");

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  DB_SERVER: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive().default(1433),
  DB_NAME: z.string().min(1).default("ShopCart"),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string().min(1),
  DB_ENCRYPT: booleanFromString,
  DB_TRUST_SERVER_CERTIFICATE: booleanFromString,
  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_TTL: z.string().default("15m"),
  REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(7),
  CORS_ORIGINS: z.string().default("http://localhost:5173"),
  RESERVATION_MINUTES: z.coerce.number().int().positive().default(15),
  RESERVATION_SWEEP_SECONDS: z.coerce.number().int().positive().default(60),
  CART_ABANDON_MINUTES: z.coerce.number().int().positive().default(1440),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  console.error("Variables de entorno inválidas:", z.flattenError(parsed.error).fieldErrors);
  process.exit(1);
}

export const env = {
  ...parsed.data,
  corsOrigins: parsed.data.CORS_ORIGINS.split(",").map((origin) => origin.trim()),
};
