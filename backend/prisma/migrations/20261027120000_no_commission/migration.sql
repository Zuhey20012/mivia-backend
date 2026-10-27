-- Malvoya takes no commission (2.13.0): new stores start at 0 % and every existing store is set to 0 %.
-- Orders keep the commission they were placed with (Accounting Act); only new orders are affected.
ALTER TABLE "Store" ALTER COLUMN "commissionRate" SET DEFAULT 0;
UPDATE "Store" SET "commissionRate" = 0 WHERE "commissionRate" <> 0;
