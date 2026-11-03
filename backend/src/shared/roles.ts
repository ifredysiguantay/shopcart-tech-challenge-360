export const Role = {
  Cliente: 1,
  Operador: 2,
  Administrador: 3,
} as const;

export type RoleId = (typeof Role)[keyof typeof Role];

export const isStaff = (role: RoleId): boolean => role === Role.Operador || role === Role.Administrador;
