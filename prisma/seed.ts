import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Seeding Mivia database...");

  // Admin user
  const adminHash = await bcrypt.hash("Admin1234!", 12);
  const admin = await prisma.user.upsert({
    where: { email: "admin@mivia.app" },
    update: {},
    create: { name: "Mivia Admin", email: "admin@mivia.app", passwordHash: adminHash, role: "ADMIN" },
  });

  // Vendor users
  const vendorHash = await bcrypt.hash("Vendor1234!", 12);

  const vendor1 = await prisma.user.upsert({
    where: { email: "sakura@mivia.app" },
    update: {},
    create: { name: "Sakura", email: "sakura@mivia.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  const vendor2 = await prisma.user.upsert({
    where: { email: "eco.belle@mivia.app" },
    update: {},
    create: { name: "Eco Belle", email: "eco.belle@mivia.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  const vendor3 = await prisma.user.upsert({
    where: { email: "thrift.nora@mivia.app" },
    update: {},
    create: { name: "Nora Vintage", email: "thrift.nora@mivia.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  // Stores
  const store1 = await prisma.store.upsert({
    where: { ownerId: vendor1.id },
    update: {},
    create: {
      ownerId: vendor1.id, name: "Sakura Boutique", category: "APPAREL",
      description: "Elegant Asian-inspired fashion for modern women",
      isVerified: true, isEcoFriendly: false, isHomeBased: false,
      address: "Aleksanterinkatu 15, Helsinki", latitude: 60.1695, longitude: 24.9354,
      rating: 4.8, totalReviews: 124,
    },
  });

  const store2 = await prisma.store.upsert({
    where: { ownerId: vendor2.id },
    update: {},
    create: {
      ownerId: vendor2.id, name: "Eco Belle Beauty", category: "COSMETICS",
      description: "100% natural, cruelty-free cosmetics and skincare",
      isVerified: true, isEcoFriendly: true, isHomeBased: false,
      address: "Fredrikinkatu 22, Helsinki", latitude: 60.163, longitude: 24.937,
      rating: 4.9, totalReviews: 89,
    },
  });

  const store3 = await prisma.store.upsert({
    where: { ownerId: vendor3.id },
    update: {},
    create: {
      ownerId: vendor3.id, name: "Nora's Thrift Corner", category: "THRIFT",
      description: "Curated second-hand gems from the comfort of home",
      isVerified: true, isEcoFriendly: true, isHomeBased: true,
      address: "Kallio, Helsinki", latitude: 60.182, longitude: 24.95,
      rating: 4.7, totalReviews: 67,
    },
  });

  // Products
  await prisma.product.createMany({
    skipDuplicates: true,
    data: [
      // Sakura Boutique - Apparel
      { storeId: store1.id, name: "Cherry Blossom Dress", category: "Dress", condition: "NEW", canBeSold: true, salePriceCents: 8900, canBeRented: true, rentalDayCents: 1200, depositCents: 5000, stockQuantity: 5, isEcoFriendly: false, images: ["https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800"] },
      { storeId: store1.id, name: "Silk Evening Blouse", category: "Top", condition: "NEW", canBeSold: true, salePriceCents: 5500, canBeRented: false, stockQuantity: 8, images: ["https://images.unsplash.com/photo-1564257631407-4deb1f99d992?w=800"] },
      { storeId: store1.id, name: "Linen Wide-Leg Trousers", category: "Pants", condition: "NEW", canBeSold: true, salePriceCents: 6200, canBeRented: false, stockQuantity: 6, isEcoFriendly: true, images: ["https://images.unsplash.com/photo-1506629082955-511b1aa562c8?w=800"] },

      // Eco Belle - Cosmetics
      { storeId: store2.id, name: "Rose Hip Face Serum", category: "Skincare", condition: "NEW", canBeSold: true, salePriceCents: 3499, stockQuantity: 20, isEcoFriendly: true, isHandmade: true, tags: ["vegan","natural","anti-aging"], images: ["https://images.unsplash.com/photo-1620916566398-39f1143ab7be?w=800"] },
      { storeId: store2.id, name: "Bamboo Lip Palette", category: "Makeup", condition: "NEW", canBeSold: true, salePriceCents: 2299, stockQuantity: 15, isEcoFriendly: true, images: ["https://images.unsplash.com/photo-1586495777744-4e6232bf7049?w=800"] },
      { storeId: store2.id, name: "Argan Oil Hair Mask", category: "Haircare", condition: "NEW", canBeSold: true, salePriceCents: 1899, stockQuantity: 25, isEcoFriendly: true, isHandmade: true, images: ["https://images.unsplash.com/photo-1526045612212-70caf35c14df?w=800"] },

      // Nora's Thrift - Second-hand
      { storeId: store3.id, name: "Vintage Levi's Denim Jacket", category: "Jacket", condition: "GOOD", canBeSold: true, salePriceCents: 4500, canBeRented: true, rentalDayCents: 800, depositCents: 3000, stockQuantity: 1, isSecondHand: true, isEcoFriendly: true, images: ["https://images.unsplash.com/photo-1551537482-f2075a1d41f2?w=800"] },
      { storeId: store3.id, name: "90s Floral Midi Skirt", category: "Skirt", condition: "LIKE_NEW", canBeSold: true, salePriceCents: 2800, stockQuantity: 1, isSecondHand: true, isEcoFriendly: true, images: ["https://images.unsplash.com/photo-1583496661160-fb5886a0aaaa?w=800"] },
      { storeId: store3.id, name: "Designer Silk Scarf", category: "Accessories", condition: "LIKE_NEW", canBeSold: true, salePriceCents: 3200, canBeRented: true, rentalDayCents: 500, depositCents: 2000, stockQuantity: 2, isSecondHand: true, images: ["https://images.unsplash.com/photo-1601924994987-69e26d50dc26?w=800"] },
    ],
  });

  // Couriers
  await prisma.courier.createMany({
    skipDuplicates: true,
    data: [
      { name: "Mikael K.", phone: "+358401234567", isActive: true, latitude: 60.170, longitude: 24.940 },
      { name: "Aisha R.",  phone: "+358409876543", isActive: true, latitude: 60.175, longitude: 24.955 },
      { name: "Johan P.",  phone: "+358401112233", isActive: true, latitude: 60.163, longitude: 24.930 },
    ],
  });

  // Test customer
  const customerHash = await bcrypt.hash("Customer1234!", 12);
  await prisma.user.upsert({
    where: { email: "customer@mivia.app" },
    update: {},
    create: { name: "Test Customer", email: "customer@mivia.app", passwordHash: customerHash, role: "CUSTOMER" },
  });

  console.log("✅ Seed complete!");
  console.log("  admin@mivia.app     / Admin1234!");
  console.log("  customer@mivia.app  / Customer1234!");
  console.log("  sakura@mivia.app    / Vendor1234!");
}

main().catch(console.error).finally(() => prisma.$disconnect());
