-- Privacy fixes (2.16.1): when the stale-position job cleared a courier's position (admin shows "no position")
ALTER TABLE "Courier" ADD COLUMN "locationExpiredAt" TIMESTAMP(3);
