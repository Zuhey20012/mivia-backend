-- 2.16.0: age confirmation, optional-email opt-out, the withdrawal function and copyright/trademark notices

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "ageConfirmedAt" TIMESTAMP(3),
ADD COLUMN     "emailMarketingOptOutAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Return" ADD COLUMN     "withdrawal" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "withdrawalAckSentAt" TIMESTAMP(3),
ADD COLUMN     "withdrawalAckChannel" TEXT;

-- AlterTable
ALTER TABLE "DropReport" ADD COLUMN     "ipNotice" JSONB;

-- AlterTable
ALTER TABLE "DropCommentReport" ADD COLUMN     "ipNotice" JSONB;

-- AlterTable
ALTER TABLE "ProductReport" ADD COLUMN     "ipNotice" JSONB;
