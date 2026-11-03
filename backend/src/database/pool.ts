import sql from "mssql";
import { env } from "../config/env.js";

export function buildConfig(database: string): sql.config {
  return {
    server: env.DB_SERVER,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database,
    options: { encrypt: env.DB_ENCRYPT, trustServerCertificate: env.DB_TRUST_SERVER_CERTIFICATE },
    pool: { max: 20, min: 0, idleTimeoutMillis: 30_000 },
    requestTimeout: 30_000,
  };
}

let pool: Promise<sql.ConnectionPool> | undefined;

export function getPool(): Promise<sql.ConnectionPool> {
  pool ??= new sql.ConnectionPool(buildConfig(env.DB_NAME)).connect().catch((error) => {
    pool = undefined;
    throw error;
  });
  return pool;
}

export async function closePool(): Promise<void> {
  if (pool) {
    await (await pool).close();
    pool = undefined;
  }
}
