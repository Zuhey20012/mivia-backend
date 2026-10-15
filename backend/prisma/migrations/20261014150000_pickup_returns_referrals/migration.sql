-- 2.8.0: Reserve & collect (pickup orders with a handover code), per-item returns, referrals, personal promo
-- codes and an admin audit log (per-store commission changes). New columns are nullable or have defaults,
-- so existing orders stay DELIVERY orders and existing returns cover the whole order.
-- Also (security review of 2.7): courier position freshness, payout transfers linked to the charge,
-- import drafts that publishing may show, and a daily cap on photos copied per store.
-- CreateEnum
CREATE TYPE "Fulfilment" AS ENUM ('DELIVERY', 'PICKUP');

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "fulfilment" "Fulfilment" NOT NULL DEFAULT 'DELIVERY',
ADD COLUMN     "pickupCode" TEXT,
ADD COLUMN     "pickupFailedAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "pickupLockedUntil" TIMESTAMP(3),
ADD COLUMN     "pickupRemindedAt" TIMESTAMP(3),
ADD COLUMN     "readyAt" TIMESTAMP(3),
ADD COLUMN     "referrerId" INTEGER;

-- AlterTable
ALTER TABLE "PromoCode" ADD COLUMN     "userId" INTEGER;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "referralCode" TEXT;

-- CreateTable
CREATE TABLE "ReturnItem" (
    "id" SERIAL NOT NULL,
    "returnId" INTEGER NOT NULL,
    "orderItemId" INTEGER NOT NULL,
    "quantity" INTEGER NOT NULL,

    CONSTRAINT "ReturnItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Referral" (
    "id" SERIAL NOT NULL,
    "referrerId" INTEGER NOT NULL,
    "refereeId" INTEGER NOT NULL,
    "orderId" INTEGER NOT NULL,
    "rewardedAt" TIMESTAMP(3),
    "rewardPromoCodeId" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Referral_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminAuditLog" (
    "id" SERIAL NOT NULL,
    "adminId" INTEGER NOT NULL,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityId" INTEGER NOT NULL,
    "oldValue" JSONB,
    "newValue" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ReturnItem_orderItemId_idx" ON "ReturnItem"("orderItemId");

-- CreateIndex
CREATE UNIQUE INDEX "ReturnItem_returnId_orderItemId_key" ON "ReturnItem"("returnId", "orderItemId");

-- CreateIndex
CREATE UNIQUE INDEX "Referral_refereeId_key" ON "Referral"("refereeId");

-- CreateIndex
CREATE UNIQUE INDEX "Referral_orderId_key" ON "Referral"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "Referral_rewardPromoCodeId_key" ON "Referral"("rewardPromoCodeId");

-- CreateIndex
CREATE INDEX "Referral_referrerId_createdAt_idx" ON "Referral"("referrerId", "createdAt");

-- CreateIndex
CREATE INDEX "AdminAuditLog_entity_entityId_createdAt_idx" ON "AdminAuditLog"("entity", "entityId", "createdAt");

-- CreateIndex
CREATE INDEX "Order_fulfilment_status_readyAt_idx" ON "Order"("fulfilment", "status", "readyAt");

-- CreateIndex
CREATE INDEX "Order_referrerId_idx" ON "Order"("referrerId");

-- CreateIndex
CREATE INDEX "PromoCode_userId_idx" ON "PromoCode"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "User_referralCode_key" ON "User"("referralCode");

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_referrerId_fkey" FOREIGN KEY ("referrerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnItem" ADD CONSTRAINT "ReturnItem_returnId_fkey" FOREIGN KEY ("returnId") REFERENCES "Return"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnItem" ADD CONSTRAINT "ReturnItem_orderItemId_fkey" FOREIGN KEY ("orderItemId") REFERENCES "OrderItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromoCode" ADD CONSTRAINT "PromoCode_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_referrerId_fkey" FOREIGN KEY ("referrerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_refereeId_fkey" FOREIGN KEY ("refereeId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_rewardPromoCodeId_fkey" FOREIGN KEY ("rewardPromoCodeId") REFERENCES "PromoCode"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AlterTable
ALTER TABLE "Courier" ADD COLUMN     "locationAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "ImportJob" ADD COLUMN     "uploads" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "Payout" ADD COLUMN     "linkedToCharge" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Product" ADD COLUMN     "importDraft" BOOLEAN NOT NULL DEFAULT false;

-- Imported drafts of jobs that were never published can still be published; anything else stays as the store left it
UPDATE "Product" p SET "importDraft" = true
WHERE p."importJobId" IS NOT NULL AND p."isAvailable" = false
  AND EXISTS (SELECT 1 FROM "ImportJob" j WHERE j.id = p."importJobId" AND j."publishedAt" IS NULL);
