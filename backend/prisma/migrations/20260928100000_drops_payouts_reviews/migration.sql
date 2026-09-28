-- CreateEnum
CREATE TYPE "SellerType" AS ENUM ('BUSINESS', 'PRIVATE');

-- CreateEnum
CREATE TYPE "MediaKind" AS ENUM ('VIDEO', 'IMAGE');

-- CreateEnum
CREATE TYPE "DropStatus" AS ENUM ('PROCESSING', 'READY', 'FAILED', 'REMOVED');

-- CreateEnum
CREATE TYPE "ReportStatus" AS ENUM ('OPEN', 'ACTIONED', 'DISMISSED');

-- CreateEnum
CREATE TYPE "PayoutParty" AS ENUM ('STORE', 'COURIER');

-- CreateEnum
CREATE TYPE "PayoutStatus" AS ENUM ('WAITING_FOR_ACCOUNT', 'SCHEDULED', 'PAID', 'CANCELLED', 'FAILED');

-- AlterTable
ALTER TABLE "Store" ADD COLUMN     "businessId" TEXT,
ADD COLUMN     "payoutsEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "prepMinutes" INTEGER NOT NULL DEFAULT 10,
ADD COLUMN     "sellerType" "SellerType" NOT NULL DEFAULT 'BUSINESS',
ADD COLUMN     "stripeAccountId" TEXT;

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "acceptedAt" TIMESTAMP(3),
ADD COLUMN     "courierFeeCents" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "deliveredLat" DOUBLE PRECISION,
ADD COLUMN     "deliveredLng" DOUBLE PRECISION,
ADD COLUMN     "deliveryProofPublicId" TEXT,
ADD COLUMN     "handoverMethod" TEXT,
ADD COLUMN     "pickedUpAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Courier" ADD COLUMN     "payoutsEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "rating" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN     "stripeAccountId" TEXT,
ADD COLUMN     "totalRatings" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "PriceChange" (
    "id" SERIAL NOT NULL,
    "productId" INTEGER NOT NULL,
    "priceCents" INTEGER NOT NULL,
    "changedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PriceChange_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Drop" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "productId" INTEGER NOT NULL,
    "caption" TEXT,
    "mediaKind" "MediaKind" NOT NULL,
    "mediaPublicId" TEXT NOT NULL,
    "durationSec" DOUBLE PRECISION,
    "width" INTEGER,
    "height" INTEGER,
    "status" "DropStatus" NOT NULL DEFAULT 'PROCESSING',
    "removedReason" TEXT,
    "likeCount" INTEGER NOT NULL DEFAULT 0,
    "viewCount" INTEGER NOT NULL DEFAULT 0,
    "shareCount" INTEGER NOT NULL DEFAULT 0,
    "completeCount" INTEGER NOT NULL DEFAULT 0,
    "watchSeconds" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Drop_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DropLike" (
    "dropId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropLike_pkey" PRIMARY KEY ("dropId","userId")
);

-- CreateTable
CREATE TABLE "DropView" (
    "dropId" INTEGER NOT NULL,
    "viewerKey" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "completed" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "DropView_pkey" PRIMARY KEY ("dropId","viewerKey","day")
);

-- CreateTable
CREATE TABLE "DropReport" (
    "id" SERIAL NOT NULL,
    "dropId" INTEGER NOT NULL,
    "reporterId" INTEGER,
    "reason" TEXT NOT NULL,
    "details" TEXT,
    "status" "ReportStatus" NOT NULL DEFAULT 'OPEN',
    "resolvedById" INTEGER,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Favorite" (
    "userId" INTEGER NOT NULL,
    "productId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Favorite_pkey" PRIMARY KEY ("userId","productId")
);

-- CreateTable
CREATE TABLE "Review" (
    "id" SERIAL NOT NULL,
    "orderId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "storeId" INTEGER NOT NULL,
    "courierId" INTEGER,
    "storeRating" INTEGER NOT NULL,
    "courierRating" INTEGER,
    "comment" TEXT,
    "isHidden" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Review_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeviceToken" (
    "token" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "platform" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeviceToken_pkey" PRIMARY KEY ("token")
);

-- CreateTable
CREATE TABLE "Payout" (
    "id" SERIAL NOT NULL,
    "orderId" INTEGER NOT NULL,
    "party" "PayoutParty" NOT NULL,
    "storeId" INTEGER,
    "courierId" INTEGER,
    "amountCents" INTEGER NOT NULL,
    "status" "PayoutStatus" NOT NULL,
    "releaseAt" TIMESTAMP(3) NOT NULL,
    "stripeTransferId" TEXT,
    "failureReason" TEXT,
    "paidAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Payout_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PriceChange_productId_changedAt_idx" ON "PriceChange"("productId", "changedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Drop_mediaPublicId_key" ON "Drop"("mediaPublicId");

-- CreateIndex
CREATE INDEX "Drop_status_publishedAt_idx" ON "Drop"("status", "publishedAt");

-- CreateIndex
CREATE INDEX "Drop_storeId_createdAt_idx" ON "Drop"("storeId", "createdAt");

-- CreateIndex
CREATE INDEX "Drop_productId_idx" ON "Drop"("productId");

-- CreateIndex
CREATE INDEX "DropLike_userId_idx" ON "DropLike"("userId");

-- CreateIndex
CREATE INDEX "DropReport_status_createdAt_idx" ON "DropReport"("status", "createdAt");

-- CreateIndex
CREATE INDEX "DropReport_dropId_idx" ON "DropReport"("dropId");

-- CreateIndex
CREATE INDEX "Favorite_productId_idx" ON "Favorite"("productId");

-- CreateIndex
CREATE UNIQUE INDEX "Review_orderId_key" ON "Review"("orderId");

-- CreateIndex
CREATE INDEX "Review_storeId_createdAt_idx" ON "Review"("storeId", "createdAt");

-- CreateIndex
CREATE INDEX "Review_courierId_idx" ON "Review"("courierId");

-- CreateIndex
CREATE INDEX "DeviceToken_userId_idx" ON "DeviceToken"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Payout_stripeTransferId_key" ON "Payout"("stripeTransferId");

-- CreateIndex
CREATE INDEX "Payout_status_releaseAt_idx" ON "Payout"("status", "releaseAt");

-- CreateIndex
CREATE INDEX "Payout_storeId_createdAt_idx" ON "Payout"("storeId", "createdAt");

-- CreateIndex
CREATE INDEX "Payout_courierId_createdAt_idx" ON "Payout"("courierId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Payout_orderId_party_key" ON "Payout"("orderId", "party");

-- CreateIndex
CREATE UNIQUE INDEX "Store_stripeAccountId_key" ON "Store"("stripeAccountId");

-- CreateIndex
CREATE UNIQUE INDEX "Courier_stripeAccountId_key" ON "Courier"("stripeAccountId");

-- AddForeignKey
ALTER TABLE "PriceChange" ADD CONSTRAINT "PriceChange_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Drop" ADD CONSTRAINT "Drop_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Drop" ADD CONSTRAINT "Drop_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropLike" ADD CONSTRAINT "DropLike_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropLike" ADD CONSTRAINT "DropLike_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropView" ADD CONSTRAINT "DropView_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropReport" ADD CONSTRAINT "DropReport_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_courierId_fkey" FOREIGN KEY ("courierId") REFERENCES "Courier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceToken" ADD CONSTRAINT "DeviceToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payout" ADD CONSTRAINT "Payout_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payout" ADD CONSTRAINT "Payout_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payout" ADD CONSTRAINT "Payout_courierId_fkey" FOREIGN KEY ("courierId") REFERENCES "Courier"("id") ON DELETE SET NULL ON UPDATE CASCADE;


-- Backfill: existing products get their current price as the first price-history entry,
-- and existing orders pay the courier the delivery fee (the rule used so far).
INSERT INTO "PriceChange" ("productId", "priceCents", "changedAt")
SELECT "id", "salePriceCents", "createdAt" FROM "Product" WHERE "salePriceCents" IS NOT NULL;

UPDATE "Order" SET "courierFeeCents" = "deliveryFeeCents" WHERE "courierFeeCents" = 0;

-- CreateTable
CREATE TABLE "JobLease" (
    "name" TEXT NOT NULL,
    "lockedUntil" TIMESTAMP(3) NOT NULL,
    "lastRunAt" TIMESTAMP(3),

    CONSTRAINT "JobLease_pkey" PRIMARY KEY ("name")
);
