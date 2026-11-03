import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sql from "mssql";
import { env } from "../config/env.js";
import { buildConfig } from "./pool.js";

const scriptsDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../database/scripts");
const CREATE_DATABASE_SCRIPT = "001_CrearBaseDatos.sql";

function splitBatches(script: string): string[] {
  return script
    .split(/^\s*GO\s*$/gim)
    .map((batch) => batch.trim())
    .filter(Boolean);
}

async function runBatches(pool: sql.ConnectionPool, script: string): Promise<void> {
  for (const batch of splitBatches(script)) {
    await pool.request().batch(batch);
  }
}

async function dropDatabase(): Promise<void> {
  if (env.NODE_ENV === "production") throw new Error("db:reset está deshabilitado en producción.");

  const master = await new sql.ConnectionPool(buildConfig("master")).connect();
  try {
    await master
      .request()
      .input("name", sql.NVarChar(128), env.DB_NAME)
      .batch(`
        DECLARE @sql NVARCHAR(400) = N'ALTER DATABASE ' + QUOTENAME(@name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ' + QUOTENAME(@name);
        IF DB_ID(@name) IS NOT NULL EXEC sp_executesql @sql`);
    console.log(`Base de datos ${env.DB_NAME} eliminada.`);
  } finally {
    await master.close();
  }
}

async function ensureDatabase(): Promise<void> {
  const master = await new sql.ConnectionPool(buildConfig("master")).connect();
  try {
    await runBatches(master, await readFile(path.join(scriptsDirectory, CREATE_DATABASE_SCRIPT), "utf8"));
  } finally {
    await master.close();
  }
}

async function migrate(): Promise<void> {
  if (process.argv.includes("--reset")) await dropDatabase();
  await ensureDatabase();
  const pool = await new sql.ConnectionPool(buildConfig(env.DB_NAME)).connect();

  try {
    await pool.request().batch(`
      IF OBJECT_ID(N'SchemaMigracion') IS NULL
        CREATE TABLE SchemaMigracion (
          Script  NVARCHAR(200) NOT NULL CONSTRAINT PK_SchemaMigracion PRIMARY KEY,
          Fecha   DATETIME2(3)  NOT NULL CONSTRAINT DF_SchemaMigracion_Fecha DEFAULT SYSUTCDATETIME()
        )`);

    const applied = new Set(
      (await pool.request().query<{ Script: string }>("SELECT Script FROM SchemaMigracion")).recordset.map((r) => r.Script),
    );

    const scripts = (await readdir(scriptsDirectory)).filter((file) => file.endsWith(".sql")).sort();

    for (const script of scripts) {
      if (script === CREATE_DATABASE_SCRIPT || applied.has(script)) continue;
      console.log(`Aplicando ${script}`);
      await runBatches(pool, await readFile(path.join(scriptsDirectory, script), "utf8"));
      await pool.request().input("script", sql.NVarChar(200), script).query("INSERT SchemaMigracion (Script) VALUES (@script)");
    }
    console.log("Base de datos al día.");
  } finally {
    await pool.close();
  }
}

migrate().catch((error) => {
  console.error(error);
  process.exit(1);
});
