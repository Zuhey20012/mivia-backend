-- AlterTable
ALTER TABLE "Courier" ADD COLUMN     "locationDisclosureAt" TIMESTAMP(3),
ADD COLUMN     "readyForApprovalAt" TIMESTAMP(3),
ADD COLUMN     "vehicleType" TEXT;

-- AlterTable
ALTER TABLE "Store" ADD COLUMN     "businessCheckStatus" TEXT,
ADD COLUMN     "businessCheckedAt" TIMESTAMP(3),
ADD COLUMN     "businessRegisteredAt" DATE,
ADD COLUMN     "businessRegisteredName" TEXT,
ADD COLUMN     "readyForApprovalAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "LegalVersion" (
    "id" SERIAL NOT NULL,
    "doc" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "textSnapshot" TEXT NOT NULL,
    "sha256" TEXT NOT NULL,
    "publishedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "effectiveAt" TIMESTAMP(3) NOT NULL,
    "summaryEn" TEXT NOT NULL,
    "summaryFi" TEXT NOT NULL,
    "noticeDays" INTEGER NOT NULL,
    "legalObligation" BOOLEAN NOT NULL DEFAULT false,
    "legalObligationReason" TEXT,
    "publishedById" INTEGER,
    "notifiedAt" TIMESTAMP(3),
    "notifiedCount" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "LegalVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AgreementAcceptance" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "doc" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ip" TEXT,
    "userAgent" TEXT,
    "appVersion" TEXT,
    "method" TEXT NOT NULL,

    CONSTRAINT "AgreementAcceptance_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "LegalVersion_doc_effectiveAt_idx" ON "LegalVersion"("doc", "effectiveAt");

-- CreateIndex
CREATE UNIQUE INDEX "LegalVersion_doc_version_key" ON "LegalVersion"("doc", "version");

-- CreateIndex
CREATE INDEX "AgreementAcceptance_doc_version_idx" ON "AgreementAcceptance"("doc", "version");

-- CreateIndex
CREATE UNIQUE INDEX "AgreementAcceptance_userId_doc_version_key" ON "AgreementAcceptance"("userId", "doc", "version");

-- CreateIndex
CREATE INDEX "Courier_isApproved_readyForApprovalAt_idx" ON "Courier"("isApproved", "readyForApprovalAt");

-- CreateIndex
CREATE INDEX "Store_isVerified_readyForApprovalAt_idx" ON "Store"("isVerified", "readyForApprovalAt");

-- AddForeignKey
ALTER TABLE "AgreementAcceptance" ADD CONSTRAINT "AgreementAcceptance_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: accounts that accepted their agreement at registration (2.10: User.termsAcceptedAt + termsVersion)
-- get an acceptance record for exactly that version. The document follows from the version's file name.
INSERT INTO "AgreementAcceptance" ("userId", "doc", "version", "acceptedAt", "method")
SELECT u."id",
       CASE split_part(u."termsVersion", '@', 1)
         WHEN 'vendor_terms' THEN 'seller-terms'
         WHEN 'courier_agreement' THEN 'courier-agreement'
         ELSE 'terms'
       END,
       u."termsVersion",
       COALESCE(u."termsAcceptedAt", u."createdAt"),
       'register'
FROM "User" u
WHERE u."termsVersion" IS NOT NULL
ON CONFLICT ("userId", "doc", "version") DO NOTHING;
