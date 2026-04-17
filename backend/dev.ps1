# dev.ps1
param()
$backend = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "Starting DB and Redis..."
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db redis
Start-Sleep -Seconds 2

Write-Host "Installing dependencies (if missing)..."
Push-Location $backend
if (-not (Test-Path node_modules)) { npm ci }

Write-Host "Generating Prisma client..."
npx prisma generate

Write-Host "Running migrations (if needed)..."
npx prisma migrate dev --name init

Write-Host "Seeding DB..."
npx ts-node prisma/seed.ts

Write-Host "Starting backend (ts-node-dev) in new terminal..."
Start-Process powershell -ArgumentList "-NoExit","-Command","cd `"$backend`"; npm run dev"

Write-Host "Starting worker in new terminal..."
Start-Process powershell -ArgumentList "-NoExit","-Command","cd `"$backend`"; npm run worker:dev"

Pop-Location
Write-Host "Dev environment started. Backend at http://localhost:4000"
