-- Indexes from docs/scaling/indexes.md: the order watchdog (1), product search with ILIKE (2, pg_trgm) and
-- case-insensitive email lookups on sign-in (3). pg_trgm is a trusted extension (the database owner can create it).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- CreateIndex
CREATE INDEX "Order_status_paymentStatus_paidAt_idx" ON "Order"("status", "paymentStatus", "paidAt");

-- CreateIndex
CREATE INDEX "Order_status_paymentStatus_createdAt_idx" ON "Order"("status", "paymentStatus", "createdAt");

-- CreateIndex
CREATE INDEX "Product_name_idx" ON "Product" USING GIN ("name" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "Product_description_idx" ON "Product" USING GIN ("description" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "Product_category_idx" ON "Product" USING GIN ("category" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "Product_tags_idx" ON "Product" USING GIN ("tags");

-- CreateIndex
CREATE INDEX "Store_name_idx" ON "Store" USING GIN ("name" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "User_email_idx" ON "User" USING GIN ("email" gin_trgm_ops);

