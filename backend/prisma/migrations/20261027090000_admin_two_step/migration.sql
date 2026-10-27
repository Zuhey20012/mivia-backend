-- Two-step sign-in with an authenticator app (admins, since 2.13.0)
ALTER TABLE "User" ADD COLUMN "totpSecret" TEXT,
ADD COLUMN "totpEnabledAt" TIMESTAMP(3),
ADD COLUMN "totpLastStep" INTEGER,
ADD COLUMN "totpRecoveryCodes" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "totpFailures" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "totpLockedUntil" TIMESTAMP(3);
