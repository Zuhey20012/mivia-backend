# Prisma 7 needs Node ^20.19 / ^22.12 / >=24
FROM node:22-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
# Dev dependencies stay installed: TypeScript builds the app and the Prisma CLI runs migrations at start-up
RUN npm ci --include=dev

COPY prisma.config.ts tsconfig.json ./
COPY prisma ./prisma
COPY src ./src
RUN npx prisma generate && npm run build

ENV NODE_ENV=production
USER node
EXPOSE 4000
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]
