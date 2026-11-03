# API de ShopCart

Base: `http://localhost:3000/api`. JSON en request y response. Autenticación con `Authorization: Bearer <accessToken>`.

Errores con formato uniforme:

```json
{ "error": { "code": "BUSINESS_RULE", "message": "El cupón está vencido.", "details": {} } }
```

| HTTP | `code`             | Cuándo                                                       |
|------|--------------------|--------------------------------------------------------------|
| 400  | `VALIDATION_ERROR` | Cuerpo, query o parámetros que no cumplen el esquema (`details` trae los campos) |
| 401  | `UNAUTHORIZED`     | Sin token, token inválido o expirado, credenciales incorrectas |
| 403  | `FORBIDDEN`        | Rol insuficiente o recurso de otro cliente                    |
| 404  | `NOT_FOUND`        | El recurso no existe                                          |
| 409  | `CONFLICT`         | Duplicado, existencia insuficiente, reserva vencida, clave de idempotencia reutilizada |
| 422  | `BUSINESS_RULE`    | Regla de negocio (cupón inválido, transición no permitida, devolución excedida…) |
| 429  | `RATE_LIMITED`     | Demasiados intentos en `/auth`                                |

Listados paginados responden `{ "data": [...], "pagination": { "page", "pageSize", "total" } }` y aceptan `page` y `pageSize` (máx. 100).

Roles: **C** Cliente · **O** Operador · **A** Administrador · **—** público.

## Autenticación

| Método | Ruta | Rol | Descripción |
|---|---|---|---|
| POST | `/auth/register` | — | Registra un cliente (`correo`, `password` ≥ 8 con letras y números, `nombre`) y abre sesión |
| POST | `/auth/login` | — | Devuelve `accessToken` (15 min) y `refreshToken`. Si se envía `X-Cart-Token`, fusiona el carrito de invitado |
| POST | `/auth/refresh` | — | Rota el refresh token. Reutilizar uno ya rotado revoca todas las sesiones del usuario |
| POST | `/auth/logout` | — | Revoca el refresh token |
| GET | `/auth/me` | C O A | Usuario actual |
| GET / POST | `/users` | A | Lista / crea usuarios (cualquier rol) |
| PATCH | `/users/:id/status` | A | `{ "activo": false }` desactiva sin borrar y revoca sus sesiones |

## Catálogo

| Método | Ruta | Rol | Descripción |
|---|---|---|---|
| GET | `/categories` | — | Categorías activas (`?incluirInactivas=true` solo para A) |
| POST / PUT / DELETE | `/categories[/:id]` | A | CRUD. No se elimina una categoría con productos o cupones |
| GET | `/products` | — | Búsqueda: `q`, `categoria`, `precioMin`, `precioMax`, `soloDisponibles`, `orden` (`nombre`\|`precio`), `direccion`, `page`, `pageSize` |
| GET | `/products/:id` | — | Producto con variantes e imágenes (los inactivos solo los ve A) |
| POST | `/products` | A | Crea producto con `variantes[]` (sku, atributos, precio, existenciaInicial) e `imagenes[]` |
| PUT | `/products/:id` | A | Actualiza datos y estado |
| DELETE | `/products/:id` | A | Elimina si no tiene historial; si lo tiene, lo **desactiva** (`resultado`) |
| POST | `/products/:id/variants` | A | Agrega variante |
| PUT | `/variants/:id` | A | Cambia atributos, precio o estado (el cambio de precio queda en la bitácora) |

## Inventario (O, A)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/inventory?q=` | Existencia física, reservada y disponible por variante |
| GET | `/inventory/variants/:id/kardex` | Movimientos con saldo acumulado |
| POST | `/inventory/movements` | `{ idVariante, tipo: "Entrada"\|"Ajuste", cantidad, motivo }`. Motivo obligatorio; no permite existencia negativa |

## Carrito

Identifica al dueño por el JWT o, si es invitado, por `X-Cart-Token` (la respuesta trae `cartToken` la primera vez). No hay ids de carrito en la URL.

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/cart` | Ítems, `subtotal`, `descuento`, `total`, `codigoCupon` |
| POST | `/cart/items` | `{ idVariante, cantidad }` suma al carrito; no excede la existencia disponible |
| PATCH | `/cart/items/:idVariante` | `{ cantidad }` fija la cantidad |
| DELETE | `/cart/items/:idVariante` | Quita el producto |
| PUT / DELETE | `/cart/coupon` | `{ codigo }` aplica / quita el cupón (requiere sesión) |

## Cupones (A)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/coupons` | Listado paginado con `usosActuales` |
| POST | `/coupons` | `codigo`, `tipo` (`Porcentaje`\|`MontoFijo`), `valor`, `fechaInicio`, `fechaFin`, `montoMinimo`, `limiteUsosTotal`, `limiteUsosPorCliente`, `idCategoria?` |
| PUT | `/coupons/:id` | Actualiza (incluye `activo`) |
| DELETE | `/coupons/:id` | Elimina o, si ya se usó, desactiva |

## Checkout (C)

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/checkout` | `{ idDireccion }`. Reserva la existencia 15 min y congela precios y descuento. Reemplaza un checkout activo previo |
| POST | `/checkout/:id/pay` | **Requiere `Idempotency-Key`**. Crea pedido, detalle, movimientos de kardex, uso de cupón y pago en una sola transacción. Repetirlo devuelve el mismo pedido (200 en vez de 201) |

## Pedidos

| Método | Ruta | Rol | Descripción |
|---|---|---|---|
| GET | `/orders` | C O A | Filtros `estado`, `cliente`, `desde`, `hasta`, `orden`, `direccion`. El cliente solo ve los suyos |
| GET | `/orders/:id` | C O A | Cabecera, detalle, historial de estados y devoluciones (403 si es de otro cliente) |
| PATCH | `/orders/:id/status` | O A | `{ estado }` avanza el ciclo de vida |
| POST | `/orders/:id/cancel` | C O A | Cancela mientras no esté despachado y reintegra existencia |
| POST | `/orders/:id/returns` | O A | `{ motivo, lineas: [{ idPedidoDetalle, cantidad }] }` devolución total o parcial |

## Reportes (A)

Todos reciben `from` y `to` (`YYYY-MM-DD`, UTC) y consideran solo pedidos **Entregados**, descontando devoluciones.

| Ruta | Descripción |
|---|---|
| `/reports/summary` | Ventas, pedidos, ticket promedio y carritos abandonados |
| `/reports/sales?agrupacion=dia\|semana\|mes` | Ventas en Q y número de pedidos por periodo |
| `/reports/sales-by-category` | Ventas y unidades por categoría |
| `/reports/top-products?top=10` | Productos más vendidos |
| `/reports/abandoned-carts` | Carritos con productos sin actividad (paginado) |

## Bitácora (A)

`GET /audit?modulo=Productos|Precios|Existencias|Cupones|Pedidos` — usuario, fecha, entidad, acción, valor anterior y nuevo.
