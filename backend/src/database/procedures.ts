import sql from "mssql";
import { getPool } from "./pool.js";

export type Row = Record<string, unknown>;

export interface ProcedureParam {
  type: sql.ISqlType | (() => sql.ISqlType);
  value: unknown;
}

export type ProcedureParams = Record<string, ProcedureParam>;

export const param = {
  int: (value: number | null | undefined): ProcedureParam => ({ type: sql.Int, value: value ?? null }),
  tinyInt: (value: number | null | undefined): ProcedureParam => ({ type: sql.TinyInt, value: value ?? null }),
  bit: (value: boolean | null | undefined): ProcedureParam => ({ type: sql.Bit, value: value ?? null }),
  text: (value: string | null | undefined, length: number | typeof sql.MAX = sql.MAX): ProcedureParam => ({
    type: sql.NVarChar(length),
    value: value ?? null,
  }),
  char: (value: string, length: number): ProcedureParam => ({ type: sql.Char(length), value }),
  money: (value: number | null | undefined): ProcedureParam => ({ type: sql.Decimal(12, 2), value: value ?? null }),
  date: (value: Date | null | undefined): ProcedureParam => ({ type: sql.Date, value: value ?? null }),
  dateTime: (value: Date | null | undefined): ProcedureParam => ({ type: sql.DateTime2(3), value: value ?? null }),
  guid: (value: string | null | undefined): ProcedureParam => ({ type: sql.UniqueIdentifier, value: value ?? null }),
  json: (value: unknown): ProcedureParam => ({
    type: sql.NVarChar(sql.MAX),
    value: value === undefined || value === null ? null : JSON.stringify(value),
  }),
};

const DEADLOCK_ERROR = 1205;
const MAX_ATTEMPTS = 3;

function toCamelCase(column: string): string {
  if (/^[A-Z0-9]+$/.test(column)) return column.toLowerCase();
  if (/^ID[A-Z]/.test(column)) return `id${column.slice(2)}`;
  return column.charAt(0).toLowerCase() + column.slice(1);
}

function camelizeRow(row: Row): Row {
  return Object.fromEntries(Object.entries(row).map(([key, value]) => [toCamelCase(key), value]));
}

async function run(procedure: string, params: ProcedureParams): Promise<Row[][]> {
  const request = (await getPool()).request();
  for (const [name, { type, value }] of Object.entries(params)) {
    request.input(name, type, value);
  }
  const result = await request.execute(procedure);
  return (result.recordsets as unknown as Row[][]).map((recordset) => recordset.map(camelizeRow));
}

export async function execute(procedure: string, params: ProcedureParams = {}): Promise<Row[][]> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await run(procedure, params);
    } catch (error) {
      const isDeadlock = (error as { number?: number }).number === DEADLOCK_ERROR;
      if (!isDeadlock || attempt >= MAX_ATTEMPTS) throw error;
    }
  }
}

export async function queryRows(procedure: string, params: ProcedureParams = {}): Promise<Row[]> {
  const [rows] = await execute(procedure, params);
  return rows ?? [];
}

export async function queryOne(procedure: string, params: ProcedureParams = {}): Promise<Row | undefined> {
  const rows = await queryRows(procedure, params);
  return rows[0];
}
