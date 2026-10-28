-- Photo drops with sound (2.13.0): more photos after the first, and an optional sound track uploaded by the store
ALTER TABLE "Drop" ADD COLUMN "extraImagePublicIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "audioPublicId" TEXT,
ADD COLUMN "audioDurationSec" DOUBLE PRECISION;
