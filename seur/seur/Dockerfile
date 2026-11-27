# Dockerfile multi-etapa optimizado para Node.js 20 con compilacion nativa de better-sqlite3

FROM node:20-bookworm-slim AS builder

WORKDIR /app

# Instalar herramientas necesarias para la compilacion de better-sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./

RUN npm ci --omit=dev

COPY . .

# Etapa final de ejecucion
FROM node:20-bookworm-slim

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Copiar artefactos y dependencias compiladas desde la etapa de construccion
COPY --from=builder /app /app

# Crear directorio de datos persistentes y asignar permisos al usuario no root
RUN mkdir -p /app/data && chown -R node:node /app

USER node

EXPOSE 3000

# Comprobacion de salud nativa con el endpoint /healthz
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 3000) + '/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "src/index.js"]
