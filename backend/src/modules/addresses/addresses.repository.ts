import { execute, param, queryOne, queryRows, type Row } from "../../database/procedures.js";

export interface AddressInput {
  alias: string;
  direccion: string;
  ciudad: string;
  departamento: string;
  telefono: string;
}

function addressParams(input: AddressInput) {
  return {
    Alias: param.text(input.alias, 50),
    Direccion: param.text(input.direccion, 250),
    Ciudad: param.text(input.ciudad, 100),
    Departamento: param.text(input.departamento, 100),
    Telefono: param.text(input.telefono, 20),
  };
}

export const addressesRepository = {
  create(idUsuario: number, input: AddressInput): Promise<Row | undefined> {
    return queryOne("SP_Direcciones_Crear", { IDUsuario: param.int(idUsuario), ...addressParams(input) });
  },

  list(idUsuario: number): Promise<Row[]> {
    return queryRows("SP_Direcciones_Listar", { IDUsuario: param.int(idUsuario) });
  },

  update(idDireccion: number, idUsuario: number, input: AddressInput): Promise<Row | undefined> {
    return queryOne("SP_Direcciones_Actualizar", {
      IDDireccion: param.int(idDireccion),
      IDUsuario: param.int(idUsuario),
      ...addressParams(input),
    });
  },

  async deactivate(idDireccion: number, idUsuario: number): Promise<void> {
    await execute("SP_Direcciones_Desactivar", { IDDireccion: param.int(idDireccion), IDUsuario: param.int(idUsuario) });
  },
};
