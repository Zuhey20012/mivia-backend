-- CreateEnum
CREATE TYPE "IncidentType" AS ENUM ('ACCIDENT', 'THREAT', 'DAMAGED', 'THEFT', 'OTHER');

-- AlterTable
ALTER TABLE "LiveMessage" ADD COLUMN     "hiddenBy" TEXT,
ADD COLUMN     "reportCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "reviewedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "cardFingerprint" TEXT,
ADD COLUMN     "disputeId" TEXT,
ADD COLUMN     "disputeReason" TEXT,
ADD COLUMN     "disputeStatus" TEXT,
ADD COLUMN     "disputedAt" TIMESTAMP(3),
ADD COLUMN     "externalRefundedCents" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "handoverPin" TEXT,
ADD COLUMN     "receiptEmail" TEXT;

-- AlterTable
ALTER TABLE "RefreshToken" ADD COLUMN     "sessionId" INTEGER,
ADD COLUMN     "usedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Store" ADD COLUMN     "changedAfterApprovalAt" TIMESTAMP(3),
ADD COLUMN     "changedFields" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "StoreFollow" ADD COLUMN     "muted" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "notifyFollowedDrops" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyLaunchAlerts" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyLives" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyReferralRewards" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "UserSession" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "device" TEXT,
    "mfa" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    "reauthUntil" TIMESTAMP(3),

    CONSTRAINT "UserSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Counter" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 0,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Counter_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "PlatformSetting" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedById" INTEGER,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlatformSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "UserNotice" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "kind" TEXT NOT NULL,
    "titleEn" TEXT NOT NULL,
    "titleFi" TEXT NOT NULL,
    "bodyEn" TEXT NOT NULL,
    "bodyFi" TEXT NOT NULL,
    "entity" TEXT,
    "entityId" INTEGER,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserNotice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OpsAlert" (
    "hash" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "firstSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OpsAlert_pkey" PRIMARY KEY ("hash")
);

-- CreateTable
CREATE TABLE "LiveMessageReport" (
    "messageId" INTEGER NOT NULL,
    "reporterId" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LiveMessageReport_pkey" PRIMARY KEY ("messageId","reporterId")
);

-- CreateTable
CREATE TABLE "CourierIncident" (
    "id" SERIAL NOT NULL,
    "courierId" INTEGER NOT NULL,
    "type" "IncidentType" NOT NULL,
    "orderId" INTEGER,
    "note" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "resolutionNote" TEXT,
    "resolvedById" INTEGER,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CourierIncident_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "UserSession_userId_revokedAt_idx" ON "UserSession"("userId", "revokedAt");

-- CreateIndex
CREATE INDEX "UserSession_revokedAt_idx" ON "UserSession"("revokedAt");

-- CreateIndex
CREATE INDEX "Counter_expiresAt_idx" ON "Counter"("expiresAt");

-- CreateIndex
CREATE INDEX "UserNotice_userId_id_idx" ON "UserNotice"("userId", "id");

-- CreateIndex
CREATE INDEX "OpsAlert_lastSeenAt_idx" ON "OpsAlert"("lastSeenAt");

-- CreateIndex
CREATE INDEX "LiveMessageReport_reporterId_idx" ON "LiveMessageReport"("reporterId");

-- CreateIndex
CREATE INDEX "CourierIncident_status_createdAt_idx" ON "CourierIncident"("status", "createdAt");

-- CreateIndex
CREATE INDEX "CourierIncident_courierId_createdAt_idx" ON "CourierIncident"("courierId", "createdAt");

-- CreateIndex
CREATE INDEX "LiveMessage_reportCount_reviewedAt_idx" ON "LiveMessage"("reportCount", "reviewedAt");

-- CreateIndex
CREATE INDEX "Order_stripePaymentIntentId_idx" ON "Order"("stripePaymentIntentId");

-- CreateIndex
CREATE INDEX "Order_cardFingerprint_idx" ON "Order"("cardFingerprint");

-- CreateIndex
CREATE INDEX "Order_disputedAt_idx" ON "Order"("disputedAt");

-- CreateIndex
CREATE INDEX "RefreshToken_sessionId_idx" ON "RefreshToken"("sessionId");

-- CreateIndex
CREATE INDEX "Store_changedAfterApprovalAt_idx" ON "Store"("changedAfterApprovalAt");

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "UserSession"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserSession" ADD CONSTRAINT "UserSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserNotice" ADD CONSTRAINT "UserNotice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveMessageReport" ADD CONSTRAINT "LiveMessageReport_messageId_fkey" FOREIGN KEY ("messageId") REFERENCES "LiveMessage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveMessageReport" ADD CONSTRAINT "LiveMessageReport_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CourierIncident" ADD CONSTRAINT "CourierIncident_courierId_fkey" FOREIGN KEY ("courierId") REFERENCES "Courier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

