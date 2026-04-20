# Use Debian-based Node so Prisma linux engines can load libssl
FROM node:20-bullseye-slim

WORKDIR /app

# Install build deps for native modules (if needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# copy package files first for cached install
COPY package.json package-lock.json* ./

# install production deps
RUN npm ci --omit=dev

# copy rest of the project
COPY . .

# build TypeScript
RUN npm run build

EXPOSE 4000
CMD ["node", "dist/index.js"]
