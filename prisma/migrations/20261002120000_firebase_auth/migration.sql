-- Firebase sign-in: users created from a Firebase ID token may have no email
-- (phone sign-in) and never have a password.
-- Written defensively because the committed migration history predates
-- "passwordHash"; databases synced with `prisma db push` already have it.

-- AlterTable
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "firebaseUid" TEXT;
ALTER TABLE "User" ALTER COLUMN "email" DROP NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name = 'User' AND column_name = 'passwordHash'
  ) THEN
    ALTER TABLE "User" ALTER COLUMN "passwordHash" DROP NOT NULL;
  END IF;
END $$;

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "User_firebaseUid_key" ON "User"("firebaseUid");
