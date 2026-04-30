import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log("🧹 Clearing Malvoya Test Data for Live Launch...");

  // Delete in order of dependencies
  await prisma.orderItem.deleteMany({});
  await prisma.order.deleteMany({});
  await prisma.product.deleteMany({});
  await prisma.store.deleteMany({});
  
  // Keep the main admin, but delete test users
  await prisma.user.deleteMany({
    where: {
      role: {
        in: ['CUSTOMER', 'COURIER', 'VENDOR']
      },
      NOT: {
        email: 'zuhey@malvoya.app' // Preserve your primary admin account
      }
    }
  });

  console.log("✨ Database is now CLEAN and ready for real production partners!");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
