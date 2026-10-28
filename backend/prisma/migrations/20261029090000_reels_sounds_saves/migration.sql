-- Reels (2.14.0): Malvoya's licensed sound library, sound mode and trim on drops, saves and "Not interested"
-- AlterTable
ALTER TABLE "Drop" ADD COLUMN     "saveCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "soundId" INTEGER,
ADD COLUMN     "soundMode" TEXT,
ADD COLUMN     "trimEndSec" DOUBLE PRECISION,
ADD COLUMN     "trimStartSec" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "DropSave" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "dropId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropSave_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DropHide" (
    "userId" INTEGER NOT NULL,
    "dropId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropHide_pkey" PRIMARY KEY ("userId","dropId")
);

-- CreateTable
CREATE TABLE "Sound" (
    "id" SERIAL NOT NULL,
    "title" TEXT NOT NULL,
    "artist" TEXT,
    "publicId" TEXT NOT NULL,
    "durationSec" DOUBLE PRECISION NOT NULL,
    "licence" TEXT NOT NULL,
    "licenceUrl" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdById" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Sound_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DropSave_userId_id_idx" ON "DropSave"("userId", "id");

-- CreateIndex
CREATE INDEX "DropSave_dropId_idx" ON "DropSave"("dropId");

-- CreateIndex
CREATE UNIQUE INDEX "DropSave_userId_dropId_key" ON "DropSave"("userId", "dropId");

-- CreateIndex
CREATE INDEX "DropHide_dropId_idx" ON "DropHide"("dropId");

-- CreateIndex
CREATE UNIQUE INDEX "Sound_publicId_key" ON "Sound"("publicId");

-- CreateIndex
CREATE INDEX "Sound_active_id_idx" ON "Sound"("active", "id");

-- CreateIndex
CREATE INDEX "Drop_soundId_status_publishedAt_idx" ON "Drop"("soundId", "status", "publishedAt");

-- AddForeignKey
ALTER TABLE "Drop" ADD CONSTRAINT "Drop_soundId_fkey" FOREIGN KEY ("soundId") REFERENCES "Sound"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropSave" ADD CONSTRAINT "DropSave_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropSave" ADD CONSTRAINT "DropSave_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropHide" ADD CONSTRAINT "DropHide_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropHide" ADD CONSTRAINT "DropHide_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

