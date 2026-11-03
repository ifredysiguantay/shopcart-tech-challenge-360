import { ZodError, z } from "zod";

export class AppError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
    readonly details?: unknown,
  ) {
    super(message);
  }
}

const businessErrors: Record<number, Pick<AppError, "status" | "code">> = {
  51000: { status: 400, code: "VALIDATION_ERROR" },
  51001: { status: 404, code: "NOT_FOUND" },
  51002: { status: 409, code: "CONFLICT" },
  51003: { status: 403, code: "FORBIDDEN" },
  51004: { status: 422, code: "BUSINESS_RULE" },
  51005: { status: 401, code: "UNAUTHORIZED" },
};

const UNIQUE_VIOLATION = [2601, 2627];
const CONSTRAINT_VIOLATION = 547;
const DEADLOCK = 1205;

export const unauthorized = (message = "Autenticación requerida.") => new AppError(401, message, "UNAUTHORIZED");
export const forbidden = (message = "No tienes permisos para esta operación.") => new AppError(403, message, "FORBIDDEN");
export const badRequest = (message: string) => new AppError(400, message, "VALIDATION_ERROR");

export function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;

  if (error instanceof ZodError) {
    return new AppError(400, "Los datos enviados no son válidos.", "VALIDATION_ERROR", z.flattenError(error).fieldErrors);
  }

  const sqlNumber = (error as { number?: number } | null)?.number;
  if (typeof sqlNumber === "number") {
    const business = businessErrors[sqlNumber];
    if (business) return new AppError(business.status, (error as Error).message, business.code);
    if (UNIQUE_VIOLATION.includes(sqlNumber)) return new AppError(409, "Ya existe un registro con ese valor único.", "CONFLICT");
    if (sqlNumber === CONSTRAINT_VIOLATION) return new AppError(422, "La operación viola una regla de integridad de datos.", "BUSINESS_RULE");
    if (sqlNumber === DEADLOCK) return new AppError(409, "El sistema está ocupado, intenta de nuevo.", "CONFLICT");
  }

  return new AppError(500, "Error interno del servidor.", "INTERNAL_ERROR");
}
