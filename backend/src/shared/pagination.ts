import { z } from "zod";
import type { Row } from "../database/procedures.js";

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export type Pagination = z.infer<typeof paginationSchema>;

export interface Page<T> {
  data: T[];
  pagination: { page: number; pageSize: number; total: number };
}

export function toPage(rows: Row[], { page, pageSize }: Pagination): Page<Row> {
  const total = Number(rows[0]?.totalRegistros ?? 0);
  const data = rows.map(({ totalRegistros: _total, ...rest }) => rest);
  return { data, pagination: { page, pageSize, total } };
}
