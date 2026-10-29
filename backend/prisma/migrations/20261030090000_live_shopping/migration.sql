-- CreateEnum
CREATE TYPE "LiveStatus" AS ENUM ('LIVE', 'ENDED');

-- AlterTable
ALTER TABLE "Store" ADD COLUMN     "liveNotifiedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "LiveStream" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "productIds" INTEGER[],
    "pinnedProductId" INTEGER,
    "roomName" TEXT NOT NULL,
    "status" "LiveStatus" NOT NULL DEFAULT 'LIVE',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),
    "lastHeartbeatAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "viewers" INTEGER NOT NULL DEFAULT 0,
    "viewerPeak" INTEGER NOT NULL DEFAULT 0,
    "likeCount" INTEGER NOT NULL DEFAULT 0,
    "endedReason" TEXT,
    "endedById" INTEGER,
    "followersNotified" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LiveStream_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LiveMessage" (
    "id" SERIAL NOT NULL,
    "liveId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "text" TEXT NOT NULL,
    "hidden" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LiveMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LiveBan" (
    "id" SERIAL NOT NULL,
    "liveId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "bannedById" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LiveBan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LiveReport" (
    "id" SERIAL NOT NULL,
    "liveId" INTEGER NOT NULL,
    "reporterId" INTEGER,
    "reason" TEXT NOT NULL,
    "details" TEXT,
    "status" "ReportStatus" NOT NULL DEFAULT 'OPEN',
    "resolvedById" INTEGER,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LiveReport_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LiveStream_roomName_key" ON "LiveStream"("roomName");

-- CreateIndex
CREATE INDEX "LiveStream_status_startedAt_idx" ON "LiveStream"("status", "startedAt");

-- CreateIndex
CREATE INDEX "LiveStream_status_lastHeartbeatAt_idx" ON "LiveStream"("status", "lastHeartbeatAt");

-- CreateIndex
CREATE INDEX "LiveStream_status_endedAt_idx" ON "LiveStream"("status", "endedAt");

-- CreateIndex
CREATE INDEX "LiveStream_storeId_createdAt_idx" ON "LiveStream"("storeId", "createdAt");

-- CreateIndex
CREATE INDEX "LiveMessage_liveId_id_idx" ON "LiveMessage"("liveId", "id");

-- CreateIndex
CREATE INDEX "LiveMessage_userId_createdAt_idx" ON "LiveMessage"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "LiveBan_userId_idx" ON "LiveBan"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "LiveBan_liveId_userId_key" ON "LiveBan"("liveId", "userId");

-- CreateIndex
CREATE INDEX "LiveReport_liveId_status_idx" ON "LiveReport"("liveId", "status");

-- CreateIndex
CREATE INDEX "LiveReport_status_createdAt_idx" ON "LiveReport"("status", "createdAt");

-- CreateIndex
CREATE INDEX "LiveReport_reporterId_idx" ON "LiveReport"("reporterId");

-- AddForeignKey
ALTER TABLE "LiveStream" ADD CONSTRAINT "LiveStream_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveMessage" ADD CONSTRAINT "LiveMessage_liveId_fkey" FOREIGN KEY ("liveId") REFERENCES "LiveStream"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveMessage" ADD CONSTRAINT "LiveMessage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveBan" ADD CONSTRAINT "LiveBan_liveId_fkey" FOREIGN KEY ("liveId") REFERENCES "LiveStream"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveBan" ADD CONSTRAINT "LiveBan_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LiveReport" ADD CONSTRAINT "LiveReport_liveId_fkey" FOREIGN KEY ("liveId") REFERENCES "LiveStream"("id") ON DELETE CASCADE ON UPDATE CASCADE;

