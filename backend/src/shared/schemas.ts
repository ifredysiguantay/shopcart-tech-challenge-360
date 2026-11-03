import { z } from "zod";

export const idParam = z.coerce.number().int().positive();

export const isoDate = z.iso.date().transform((value) => new Date(value));

export const dateRangeSchema = z.object({
  from: isoDate,
  to: isoDate,
});

export const sortDirection = z.enum(["asc", "desc"]);

export const moneyAmount = z.number().positive().multipleOf(0.01);
