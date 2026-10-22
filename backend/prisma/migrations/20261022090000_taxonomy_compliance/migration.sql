-- 2.12.0: category taxonomy, category attributes, unit prices, product safety (GPSR), certificates, product reports,
-- recalls, hygiene seal; removes the generic eco claim (Directive (EU) 2024/825). Categories are seeded and existing
-- products are mapped onto them at start-up (src/modules/catalog/seed.ts), not here.

-- CreateEnum
CREATE TYPE "Audience" AS ENUM ('WOMEN', 'MEN', 'KIDS', 'UNISEX');

-- CreateEnum
CREATE TYPE "CertificateStatus" AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');

-- CreateEnum
CREATE TYPE "RecallStatus" AS ENUM ('ACTIVE', 'CLOSED');

-- AlterEnum (stores that called themselves ECO_FRIENDLY become OTHER and are asked to choose)
UPDATE "Store" SET "category" = 'OTHER' WHERE "category" = 'ECO_FRIENDLY';
BEGIN;
CREATE TYPE "StoreCategory_new" AS ENUM ('APPAREL', 'COSMETICS', 'THRIFT', 'ACCESSORIES', 'HOME_DECOR', 'HANDMADE', 'OTHER');
ALTER TABLE "Store" ALTER COLUMN "category" TYPE "StoreCategory_new" USING ("category"::text::"StoreCategory_new");
ALTER TYPE "StoreCategory" RENAME TO "StoreCategory_old";
ALTER TYPE "StoreCategory_new" RENAME TO "StoreCategory";
DROP TYPE "public"."StoreCategory_old";
COMMIT;

-- AlterTable
ALTER TABLE "OrderItem" ADD COLUMN     "hygieneSealed" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Product" DROP COLUMN "isEcoFriendly",
ADD COLUMN     "attributes" JSONB NOT NULL DEFAULT '{}',
ADD COLUMN     "audience" "Audience" NOT NULL DEFAULT 'UNISEX',
ADD COLUMN     "batchOrSerial" TEXT,
ADD COLUMN     "categoryId" INTEGER,
ADD COLUMN     "contentAmount" DOUBLE PRECISION,
ADD COLUMN     "contentUnit" TEXT,
ADD COLUMN     "hygieneSealed" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "importHold" TEXT,
ADD COLUMN     "lockedAt" TIMESTAMP(3),
ADD COLUMN     "lockedReason" TEXT,
ADD COLUMN     "manufacturerId" INTEGER,
ADD COLUMN     "noWarnings" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "productModel" TEXT,
ADD COLUMN     "responsiblePersonId" INTEGER,
ADD COLUMN     "safetyImages" TEXT[],
ADD COLUMN     "warningsEn" TEXT,
ADD COLUMN     "warningsFi" TEXT,
ADD COLUMN     "warningsSv" TEXT;

-- AlterTable
ALTER TABLE "ProductVariant" ADD COLUMN     "colourFamily" TEXT,
ADD COLUMN     "contentAmount" DOUBLE PRECISION,
ADD COLUMN     "contentUnit" TEXT,
ADD COLUMN     "finish" TEXT,
ADD COLUMN     "measurements" JSONB,
ADD COLUMN     "shadeFamily" TEXT,
ADD COLUMN     "shadeHex" TEXT,
ADD COLUMN     "shadeName" TEXT,
ADD COLUMN     "undertone" TEXT;

-- AlterTable
ALTER TABLE "Return" ADD COLUMN     "sealIntact" BOOLEAN;

-- AlterTable
ALTER TABLE "Store" DROP COLUMN "isEcoFriendly",
ADD COLUMN     "safetyPledgeAt" TIMESTAMP(3),
ADD COLUMN     "safetyPledgeVersion" TEXT;

-- CreateTable
CREATE TABLE "Category" (
    "id" SERIAL NOT NULL,
    "slug" TEXT NOT NULL,
    "parentId" INTEGER,
    "nameEn" TEXT NOT NULL,
    "nameFi" TEXT NOT NULL,
    "icon" TEXT NOT NULL,
    "tileColor" TEXT NOT NULL,
    "sort" INTEGER NOT NULL DEFAULT 0,
    "template" TEXT,
    "isCollection" BOOLEAN NOT NULL DEFAULT false,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProductFacet" (
    "productId" INTEGER NOT NULL,
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,

    CONSTRAINT "ProductFacet_pkey" PRIMARY KEY ("productId","key","value")
);

-- CreateTable
CREATE TABLE "EconomicOperator" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "addressLine" TEXT NOT NULL,
    "postalCode" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "email" TEXT,
    "url" TEXT,
    "phone" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EconomicOperator_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Certificate" (
    "id" SERIAL NOT NULL,
    "storeId" INTEGER NOT NULL,
    "scheme" TEXT NOT NULL,
    "licenceNumber" TEXT NOT NULL,
    "holderName" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "componentDescription" TEXT,
    "validUntil" DATE NOT NULL,
    "evidenceUrl" TEXT NOT NULL,
    "publicVerifyUrl" TEXT,
    "status" "CertificateStatus" NOT NULL DEFAULT 'PENDING',
    "reviewedById" INTEGER,
    "reviewedAt" TIMESTAMP(3),
    "rejectionReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Certificate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProductCertificate" (
    "productId" INTEGER NOT NULL,
    "certificateId" INTEGER NOT NULL,

    CONSTRAINT "ProductCertificate_pkey" PRIMARY KEY ("productId","certificateId")
);

-- CreateTable
CREATE TABLE "ProductReport" (
    "id" SERIAL NOT NULL,
    "productId" INTEGER NOT NULL,
    "reporterId" INTEGER,
    "reporterEmail" TEXT,
    "reason" TEXT NOT NULL,
    "details" TEXT,
    "status" "ReportStatus" NOT NULL DEFAULT 'OPEN',
    "resolution" TEXT,
    "resolutionNote" TEXT,
    "resolvedById" INTEGER,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Recall" (
    "id" SERIAL NOT NULL,
    "title" TEXT NOT NULL,
    "reasonFi" TEXT NOT NULL,
    "reasonEn" TEXT NOT NULL,
    "reasonSv" TEXT,
    "remedyFi" TEXT NOT NULL,
    "remedyEn" TEXT NOT NULL,
    "remedySv" TEXT,
    "remedies" TEXT[],
    "contact" TEXT NOT NULL,
    "status" "RecallStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdById" INTEGER NOT NULL,
    "closedAt" TIMESTAMP(3),
    "buyersNotifiedAt" TIMESTAMP(3),
    "notifiedUsers" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Recall_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RecallProduct" (
    "recallId" INTEGER NOT NULL,
    "productId" INTEGER NOT NULL,
    "matchedBy" TEXT NOT NULL,

    CONSTRAINT "RecallProduct_pkey" PRIMARY KEY ("recallId","productId")
);

-- CreateTable
CREATE TABLE "RecallNotification" (
    "id" SERIAL NOT NULL,
    "recallId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "channel" TEXT NOT NULL,
    "delivered" BOOLEAN NOT NULL,
    "locale" TEXT NOT NULL,
    "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RecallNotification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Category_slug_key" ON "Category"("slug");

-- CreateIndex
CREATE INDEX "Category_parentId_sort_idx" ON "Category"("parentId", "sort");

-- CreateIndex
CREATE INDEX "ProductFacet_key_value_idx" ON "ProductFacet"("key", "value");

-- CreateIndex
CREATE INDEX "EconomicOperator_storeId_idx" ON "EconomicOperator"("storeId");

-- CreateIndex
CREATE INDEX "Certificate_status_createdAt_idx" ON "Certificate"("status", "createdAt");

-- CreateIndex
CREATE INDEX "Certificate_storeId_idx" ON "Certificate"("storeId");

-- CreateIndex
CREATE INDEX "ProductCertificate_certificateId_idx" ON "ProductCertificate"("certificateId");

-- CreateIndex
CREATE INDEX "ProductReport_status_createdAt_idx" ON "ProductReport"("status", "createdAt");

-- CreateIndex
CREATE INDEX "ProductReport_productId_idx" ON "ProductReport"("productId");

-- CreateIndex
CREATE INDEX "ProductReport_reporterId_idx" ON "ProductReport"("reporterId");

-- CreateIndex
CREATE INDEX "Recall_status_createdAt_idx" ON "Recall"("status", "createdAt");

-- CreateIndex
CREATE INDEX "RecallProduct_productId_idx" ON "RecallProduct"("productId");

-- CreateIndex
CREATE INDEX "RecallNotification_userId_idx" ON "RecallNotification"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "RecallNotification_recallId_userId_channel_key" ON "RecallNotification"("recallId", "userId", "channel");

-- CreateIndex
CREATE INDEX "Product_categoryId_isAvailable_idx" ON "Product"("categoryId", "isAvailable");

-- CreateIndex
CREATE INDEX "Product_manufacturerId_idx" ON "Product"("manufacturerId");

-- CreateIndex
CREATE INDEX "Product_responsiblePersonId_idx" ON "Product"("responsiblePersonId");

-- CreateIndex
CREATE INDEX "Product_gtin_idx" ON "Product"("gtin");

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_manufacturerId_fkey" FOREIGN KEY ("manufacturerId") REFERENCES "EconomicOperator"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_responsiblePersonId_fkey" FOREIGN KEY ("responsiblePersonId") REFERENCES "EconomicOperator"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Category" ADD CONSTRAINT "Category_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductFacet" ADD CONSTRAINT "ProductFacet_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EconomicOperator" ADD CONSTRAINT "EconomicOperator_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Certificate" ADD CONSTRAINT "Certificate_storeId_fkey" FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductCertificate" ADD CONSTRAINT "ProductCertificate_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductCertificate" ADD CONSTRAINT "ProductCertificate_certificateId_fkey" FOREIGN KEY ("certificateId") REFERENCES "Certificate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductReport" ADD CONSTRAINT "ProductReport_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecallProduct" ADD CONSTRAINT "RecallProduct_recallId_fkey" FOREIGN KEY ("recallId") REFERENCES "Recall"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecallProduct" ADD CONSTRAINT "RecallProduct_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecallNotification" ADD CONSTRAINT "RecallNotification_recallId_fkey" FOREIGN KEY ("recallId") REFERENCES "Recall"("id") ON DELETE CASCADE ON UPDATE CASCADE;

