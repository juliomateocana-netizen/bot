# Servicio Acortador y Redireccionador (wаllаpоp.com)

Servicio de alto rendimiento para creacion y gestion de enlaces cortos y redirecciones HTTP hacia anuncios o publicaciones, utilizando Node.js 20, Express y SQLite (`better-sqlite3`).

El sistema utiliza como dominio base `wаllаpоp.com`, donde las dos letras **"a"** corresponden al caracter cirilico `U+0430` y la letra **"o"** corresponde al caracter cirilico `U+043E`.

---

## 1. Caracteristicas tecnicas

- **Backend**: Node.js 20 con Express.
- **Base de datos**: SQLite local embebido mediante `better-sqlite3`, con modo WAL habilitado y almacenamiento en `./data/links.db`.
- **Renderizado**: Interfaz HTML y CSS limpia y responsive servida desde el propio backend, con soporte para tema claro y tema oscuro mediante `prefers-color-scheme`.
- **Cero dependencias externas en frontend**: Sin frameworks, sin paso de build y sin CDNs.
- **Codigos QR**: Generados directamente en el servidor como imagen PNG en `/:alias/qr`.
- **Seguridad**: Validacion estricta de esquemas permitidos (`http:` y `https:`), proteccion contra rutas reservadas y prevencion de inyecciones.
- **Independencia del Host**: Todos los enlaces se componen a partir de `PUBLIC_BASE_URL` para garantizar consistencia entre peticiones directas y punycode.

---

## 2. Variables de entorno

Crea o edita tu archivo `.env` tomando como base `.env.example`:

```env
# Puerto del servidor (por defecto 3000)
PORT=3000

# URL publica base (por defecto https://wаllаpоp.com)
PUBLIC_BASE_URL=https://wаllаpоp.com

# Codigo HTTP de redireccion: 302 (temporal, recomendado) o 301 (permanente)
REDIRECT_CODE=302
```

---

## 3. Despliegue y ejecucion

### Opcion A: Ejecucion directa con Node.js

1. Asegurate de tener instalado Node.js 20.
2. Instala las dependencias:
   ```bash
   npm install
   ```
3. Inicia la aplicacion:
   ```bash
   npm start
   ```
4. Abre tu navegador en `http://localhost:3000`.

### Opcion B: Despliegue con Docker y Docker Compose

1. Inicia el contenedor en segundo plano con el volumen de base de datos persistido:
   ```bash
   docker compose up -d --build
   ```
2. Consulta los registros en tiempo real:
   ```bash
   docker compose logs -f
   ```
3. Deten el contenedor:
   ```bash
   docker compose down
   ```

---

## 4. Configuracion de DNS y Dominio Cirilico (Punycode)

### Nota fundamental sobre el dominio IDN (Internationalized Domain Name)

El dominio `wаllаpоp.com` contiene caracteres homografos cirilicos:
- Primera `а`: `U+0430` (Cyrillic small letter a)
- Segunda `а`: `U+0430` (Cyrillic small letter a)
- Primera `о`: `U+043E` (Cyrillic small letter o)

Los sistemas DNS internacionales y los registradores de dominios (Cloudflare, Namecheap, GoDaddy, OVH, etc.) **no almacenan internamente caracteres Unicode**, sino su representacion estandarizada en formato **Punycode (RFC 3492)**:

```text
Forma Unicode visual: wаllаpоp.com
Forma Punycode en DNS: xn--wllpp-4vec7i.com
```

### Registros DNS a crear en tu proveedor

En el panel de gestion DNS de tu registrador o proveedor de hosting (por ejemplo Cloudflare o tu servidor de nombres), debes crear los siguientes registros apuntando al dominio en su forma Punycode `xn--wllpp-4vec7i.com`:

#### Si tienes una direccion IP fija (servidor VPS o dedicado):
- **Tipo**: `A`
- **Nombre**: `@` (o `xn--wllpp-4vec7i.com`)
- **Valor / Destino**: `IP_PUBLICA_DE_TU_SERVIDOR`
- **TTL**: Automatico o 300 segundos

- **Tipo**: `A` (o `CNAME`) para subdominio opcional www:
- **Nombre**: `www`
- **Valor / Destino**: `IP_PUBLICA_DE_TU_SERVIDOR` (o `xn--wllpp-4vec7i.com`)

#### Si utilizas un servicio de plataforma o balanceador (como Netlify, Render, Railway, etc.):
- **Tipo**: `CNAME`
- **Nombre**: `@` (o subdominio)
- **Valor / Destino**: `nombre-asignado-por-tu-proveedor.dominio.com`

> **Importante**: Al solicitar certificados SSL/TLS (Let's Encrypt o Certbot), los clientes ACME utilizan de forma nativa la cadena Punycode `xn--wllpp-4vec7i.com`.

---

## 5. Endpoints de la API y rutas

| Metodo | Ruta | Descripcion |
|---|---|---|
| `GET` | `/` | Panel de control web para crear y gestionar enlaces. |
| `POST` | `/api/links` | Crea un enlace corto. Admite `{ destino, alias? }`. Devuelve JSON. |
| `DELETE` | `/api/links/:id` | Elimina un enlace por su identificador numerico. |
| `GET` | `/:alias` | Redirige al destino con codigo 302 (o 301), suma un clic y actualiza fecha. |
| `GET` | `/:alias/qr` | Devuelve el codigo QR del enlace en formato de imagen PNG. |
| `GET` | `/healthz` | Comprobacion de estado del servicio (responde `200 ok`). |

---

## 6. Estructura de la base de datos

El archivo se almacena en `./data/links.db`. Al iniciar la aplicacion se asegura la creacion automatica de la tabla e indices:

```sql
CREATE TABLE IF NOT EXISTS links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alias TEXT NOT NULL UNIQUE,
  destino TEXT NOT NULL,
  clics INTEGER NOT NULL DEFAULT 0,
  creado_en TEXT NOT NULL DEFAULT (datetime('now')),
  ultimo_acceso TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_links_alias ON links(alias);
```
