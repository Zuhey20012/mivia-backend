-- CreateTable
CREATE TABLE "OtpCode" (
    "target" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OtpCode_pkey" PRIMARY KEY ("target")
);

-- CreateIndex
CREATE INDEX "OtpCode_expiresAt_idx" ON "OtpCode"("expiresAt");

-- CreateIndex
CREATE INDEX "RefreshToken_userId_idx" ON "RefreshToken"("userId");

-- CreateIndex
CREATE INDEX "Store_isVerified_rating_idx" ON "Store"("isVerified", "rating");

-- CreateIndex
CREATE INDEX "Product_storeId_isAvailable_idx" ON "Product"("storeId", "isAvailable");

-- CreateIndex
CREATE INDEX "ProductVariant_productId_idx" ON "ProductVariant"("productId");

-- CreateIndex
CREATE INDEX "Order_userId_createdAt_idx" ON "Order"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "Order_storeId_paymentStatus_createdAt_idx" ON "Order"("storeId", "paymentStatus", "createdAt");

-- CreateIndex
CREATE INDEX "Order_courierId_status_idx" ON "Order"("courierId", "status");

-- CreateIndex
CREATE INDEX "Order_status_paymentStatus_courierId_idx" ON "Order"("status", "paymentStatus", "courierId");

-- CreateIndex
CREATE INDEX "OrderItem_orderId_idx" ON "OrderItem"("orderId");

-- CreateIndex
CREATE INDEX "OrderItem_productId_idx" ON "OrderItem"("productId");

-- CreateIndex
CREATE INDEX "Rental_userId_createdAt_idx" ON "Rental"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "RentalItem_rentalId_idx" ON "RentalItem"("rentalId");

-- CreateIndex
CREATE INDEX "RentalItem_productId_idx" ON "RentalItem"("productId");

-- CreateIndex
CREATE INDEX "Return_userId_createdAt_idx" ON "Return"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "Return_orderId_idx" ON "Return"("orderId");

-- CreateIndex
CREATE INDEX "Courier_isApproved_isActive_idx" ON "Courier"("isApproved", "isActive");

