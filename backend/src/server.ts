import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { closePool, getPool } from "./database/pool.js";
import { execute } from "./database/procedures.js";

async function releaseExpiredReservations(): Promise<void> {
  try {
    await execute("SP_Reservas_LiberarVencidas");
  } catch (error) {
    console.error("No se pudieron liberar las reservas vencidas:", error);
  }
}

async function main(): Promise<void> {
  await getPool();

  const server = createApp().listen(env.PORT, () => {
    console.log(`ShopCart API escuchando en http://localhost:${env.PORT}`);
  });

  const sweeper = setInterval(releaseExpiredReservations, env.RESERVATION_SWEEP_SECONDS * 1000);

  const shutdown = (): void => {
    clearInterval(sweeper);
    server.close(() => {
      void closePool().finally(() => process.exit(0));
    });
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
