-- Store availability
ALTER TABLE "Store" ADD COLUMN "acceptingOrders" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Store" ADD COLUMN "openingHours" JSONB;

-- Order watchdog bookkeeping
ALTER TABLE "Order" ADD COLUMN "confirmedAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "storeRemindedAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "lastOfferAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "courierSearchNotifiedAt" TIMESTAMP(3);

-- Launch alerts
CREATE TABLE "LaunchAlert" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "area" TEXT,
    "notifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "LaunchAlert_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "LaunchAlert_userId_key" ON "LaunchAlert"("userId");
CREATE INDEX "LaunchAlert_notifiedAt_idx" ON "LaunchAlert"("notifiedAt");
ALTER TABLE "LaunchAlert" ADD CONSTRAINT "LaunchAlert_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
