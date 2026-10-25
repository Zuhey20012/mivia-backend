-- Sign in with Apple: the Apple user id opens its account first (2.12)
-- AlterTable
ALTER TABLE "User" ADD COLUMN     "appleSub" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "User_appleSub_key" ON "User"("appleSub");

