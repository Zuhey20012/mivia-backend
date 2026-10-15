-- AlterEnum
ALTER TYPE "ImportSource" ADD VALUE 'WOOCOMMERCE';

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "dispatchStartedAt" TIMESTAMP(3),
ADD COLUMN     "scheduledEnd" TIMESTAMP(3),
ADD COLUMN     "scheduledStart" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "StoreTaxInfo" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "legalName" TEXT NOT NULL,
    "dateOfBirth" DATE,
    "tinEncrypted" TEXT,
    "vatNumber" TEXT,
    "addressLine" TEXT NOT NULL,
    "postalCode" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StoreTaxInfo_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "StoreTaxInfo_storeId_key" ON "StoreTaxInfo"("storeId");

-- CreateIndex
CREATE INDEX "Order_deliveredAt_idx" ON "Order"("deliveredAt");

-- CreateIndex
CREATE INDEX "Order_paidAt_idx" ON "Order"("paidAt");

-- CreateIndex
CREATE INDEX "Order_scheduledStart_idx" ON "Order"("scheduledStart");

-- AddForeignKey
ALTER TABLE "StoreTaxInfo" ADD CONSTRAINT "StoreTaxInfo_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

