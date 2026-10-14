-- 2.7.0: transparent courier pay (breakdown, shop check-in for waiting pay) and catalogue import
-- (Shopify feed / CSV) with idempotent re-imports. New columns are nullable, so existing rows are unchanged.
-- CreateEnum
CREATE TYPE "ImportSource" AS ENUM ('SHOPIFY', 'CSV');

-- CreateEnum
CREATE TYPE "ImportStatus" AS ENUM ('QUEUED', 'RUNNING', 'DONE', 'FAILED');

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "courierArrivedAt" TIMESTAMP(3),
ADD COLUMN     "courierPay" JSONB;

-- AlterTable
ALTER TABLE "Product" ADD COLUMN     "externalId" TEXT,
ADD COLUMN     "externalSource" TEXT,
ADD COLUMN     "gtin" TEXT,
ADD COLUMN     "importJobId" INTEGER;

-- CreateTable
CREATE TABLE "ImportJob" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "source" "ImportSource" NOT NULL,
    "status" "ImportStatus" NOT NULL DEFAULT 'QUEUED',
    "sourceRef" TEXT,
    "total" INTEGER NOT NULL DEFAULT 0,
    "created" INTEGER NOT NULL DEFAULT 0,
    "updated" INTEGER NOT NULL DEFAULT 0,
    "skipped" INTEGER NOT NULL DEFAULT 0,
    "errors" JSONB NOT NULL DEFAULT '[]',
    "rightsConfirmedAt" TIMESTAMP(3) NOT NULL,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "finishedAt" TIMESTAMP(3),

    CONSTRAINT "ImportJob_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ImportJob_storeId_createdAt_idx" ON "ImportJob"("storeId", "createdAt");

-- CreateIndex
CREATE INDEX "ImportJob_status_updatedAt_idx" ON "ImportJob"("status", "updatedAt");

-- CreateIndex
CREATE INDEX "Product_importJobId_idx" ON "Product"("importJobId");

-- CreateIndex
CREATE UNIQUE INDEX "Product_storeId_externalSource_externalId_key" ON "Product"("storeId", "externalSource", "externalId");

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_importJobId_fkey" FOREIGN KEY ("importJobId") REFERENCES "ImportJob"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ImportJob" ADD CONSTRAINT "ImportJob_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

