import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Seeding Malvoya: Artisan & P2P Marketplace...");

  // Admin user
  const adminHash = await bcrypt.hash("Admin1234!", 12);
  await prisma.user.upsert({
    where: { email: "admin@malvoya.app" },
    update: {},
    create: { name: "Malvoya Admin", email: "admin@malvoya.app", passwordHash: adminHash, role: "ADMIN" },
  });

  console.log("✅ Malvoya Production Seed ready: Zero fake merchants, zero fake couriers.");
}

main().catch(console.error).finally(() => prisma.$disconnect());
