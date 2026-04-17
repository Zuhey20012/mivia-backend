# Dockerfile (replace existing)
FROM node:20-bullseye

WORKDIR /app

# Install build tools and ca-certificates
RUN apt-get update && apt-get install -y build-essential ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy package files and install production deps
COPY package.json package-lock.json* ./
RUN npm ci --production

# Copy source and build
COPY . .
RUN npm run build

EXPOSE 4000

CMD ["node", "dist/index.js"]
