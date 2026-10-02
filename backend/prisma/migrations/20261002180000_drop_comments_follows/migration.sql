-- CreateEnum
CREATE TYPE "CommentStatus" AS ENUM ('VISIBLE', 'HIDDEN', 'REMOVED');

-- AlterTable
ALTER TABLE "Drop" ADD COLUMN     "commentCount" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "DropComment" (
    "id" SERIAL NOT NULL,
    "dropId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "body" TEXT NOT NULL,
    "status" "CommentStatus" NOT NULL DEFAULT 'VISIBLE',
    "reportCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropComment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DropCommentReport" (
    "commentId" INTEGER NOT NULL,
    "reporterId" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DropCommentReport_pkey" PRIMARY KEY ("commentId","reporterId")
);

-- CreateTable
CREATE TABLE "StoreFollow" (
    "userId" INTEGER NOT NULL,
    "storeId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreFollow_pkey" PRIMARY KEY ("userId","storeId")
);

-- CreateIndex
CREATE INDEX "DropComment_dropId_status_id_idx" ON "DropComment"("dropId", "status", "id");

-- CreateIndex
CREATE INDEX "DropComment_userId_createdAt_idx" ON "DropComment"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "DropComment_status_reportCount_idx" ON "DropComment"("status", "reportCount");

-- CreateIndex
CREATE INDEX "StoreFollow_storeId_idx" ON "StoreFollow"("storeId");

-- AddForeignKey
ALTER TABLE "DropComment" ADD CONSTRAINT "DropComment_dropId_fkey" FOREIGN KEY ("dropId") REFERENCES "Drop"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropComment" ADD CONSTRAINT "DropComment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DropCommentReport" ADD CONSTRAINT "DropCommentReport_commentId_fkey" FOREIGN KEY ("commentId") REFERENCES "DropComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StoreFollow" ADD CONSTRAINT "StoreFollow_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StoreFollow" ADD CONSTRAINT "StoreFollow_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

