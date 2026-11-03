import { execute, param, queryOne, queryRows, type Row } from "../../database/procedures.js";

export interface CategoryInput {
  nombre: string;
  descripcion?: string | undefined;
}

export interface VariantInput {
  sku: string;
  atributos: Record<string, string>;
  precio: number;
}

export interface NewVariantInput extends VariantInput {
  existenciaInicial: number;
}

export interface ProductSearch {
  texto?: string | undefined;
  idCategoria?: number | undefined;
  precioMinimo?: number | undefined;
  precioMaximo?: number | undefined;
  soloDisponibles: boolean;
  incluirInactivos: boolean;
  orden: string;
  direccion: string;
  page: number;
  pageSize: number;
}

export const catalogRepository = {
  createCategory(input: CategoryInput): Promise<Row | undefined> {
    return queryOne("SP_Categorias_Crear", {
      Nombre: param.text(input.nombre, 100),
      Descripcion: param.text(input.descripcion, 500),
    });
  },

  updateCategory(idCategoria: number, input: CategoryInput & { activo: boolean }): Promise<Row | undefined> {
    return queryOne("SP_Categorias_Actualizar", {
      IDCategoria: param.int(idCategoria),
      Nombre: param.text(input.nombre, 100),
      Descripcion: param.text(input.descripcion, 500),
      Activo: param.bit(input.activo),
    });
  },

  listCategories(includeInactive: boolean): Promise<Row[]> {
    return queryRows("SP_Categorias_Listar", { IncluirInactivas: param.bit(includeInactive) });
  },

  async deleteCategory(idCategoria: number): Promise<void> {
    await execute("SP_Categorias_Eliminar", { IDCategoria: param.int(idCategoria) });
  },

  async createProduct(
    input: {
      idCategoria: number;
      nombre: string;
      descripcion: string;
      variantes: NewVariantInput[];
      imagenes?: string[] | undefined;
    },
    idUsuario: number,
  ): Promise<Row | undefined> {
    return queryOne("SP_Productos_Crear", {
      IDCategoria: param.int(input.idCategoria),
      Nombre: param.text(input.nombre, 150),
      Descripcion: param.text(input.descripcion, 2000),
      VariantesJson: param.json(input.variantes),
      ImagenesJson: param.json(input.imagenes),
      IDUsuario: param.int(idUsuario),
    });
  },

  async updateProduct(
    idProducto: number,
    input: { idCategoria: number; nombre: string; descripcion: string; activo: boolean; imagenes?: string[] | undefined },
    idUsuario: number,
  ): Promise<void> {
    await execute("SP_Productos_Actualizar", {
      IDProducto: param.int(idProducto),
      IDCategoria: param.int(input.idCategoria),
      Nombre: param.text(input.nombre, 150),
      Descripcion: param.text(input.descripcion, 2000),
      Activo: param.bit(input.activo),
      ImagenesJson: param.json(input.imagenes),
      IDUsuario: param.int(idUsuario),
    });
  },

  deleteProduct(idProducto: number, idUsuario: number): Promise<Row | undefined> {
    return queryOne("SP_Productos_Eliminar", { IDProducto: param.int(idProducto), IDUsuario: param.int(idUsuario) });
  },

  async getProduct(idProducto: number, includeInactive: boolean) {
    const [product, variants, images] = await execute("SP_Productos_Obtener", {
      IDProducto: param.int(idProducto),
      IncluirInactivos: param.bit(includeInactive),
    });
    return { ...product?.[0], variantes: variants ?? [], imagenes: (images ?? []).map((image) => image["url"]) };
  },

  searchProducts(filters: ProductSearch): Promise<Row[]> {
    return queryRows("SP_Productos_Buscar", {
      Texto: param.text(filters.texto, 100),
      IDCategoria: param.int(filters.idCategoria),
      PrecioMinimo: param.money(filters.precioMinimo),
      PrecioMaximo: param.money(filters.precioMaximo),
      SoloDisponibles: param.bit(filters.soloDisponibles),
      IncluirInactivos: param.bit(filters.incluirInactivos),
      Orden: param.text(filters.orden, 10),
      Direccion: param.text(filters.direccion, 4),
      Pagina: param.int(filters.page),
      TamanoPagina: param.int(filters.pageSize),
    });
  },

  createVariant(idProducto: number, input: NewVariantInput, idUsuario: number): Promise<Row | undefined> {
    return queryOne("SP_Variantes_Crear", {
      IDProducto: param.int(idProducto),
      SKU: param.text(input.sku, 50),
      Atributos: param.text(JSON.stringify(input.atributos), 500),
      Precio: param.money(input.precio),
      ExistenciaInicial: param.int(input.existenciaInicial),
      IDUsuario: param.int(idUsuario),
    });
  },

  async updateVariant(idVariante: number, input: VariantInput & { activo: boolean }, idUsuario: number): Promise<void> {
    await execute("SP_Variantes_Actualizar", {
      IDVariante: param.int(idVariante),
      Atributos: param.text(JSON.stringify(input.atributos), 500),
      Precio: param.money(input.precio),
      Activo: param.bit(input.activo),
      IDUsuario: param.int(idUsuario),
    });
  },
};
