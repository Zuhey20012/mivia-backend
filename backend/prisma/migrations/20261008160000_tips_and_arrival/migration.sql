-- Courier tips and the one-time "courier is arriving" notification
ALTER TABLE "Order" ADD COLUMN "tipCents" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "arrivingNotifiedAt" TIMESTAMP(3);
