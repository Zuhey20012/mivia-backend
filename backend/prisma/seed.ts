import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Seeding Malvoya: Artisan & P2P Marketplace...");

  // Admin user
  const adminHash = await bcrypt.hash("Admin1234!", 12);
  const admin = await prisma.user.upsert({
    where: { email: "admin@malvoya.app" },
    update: {},
    create: { name: "Malvoya Admin", email: "admin@malvoya.app", passwordHash: adminHash, role: "ADMIN" },
  });

  // Artisan Vendors (Real People)
  const vendorHash = await bcrypt.hash("Vendor1234!", 12);

  const vendor1 = await prisma.user.upsert({
    where: { email: "sarah.crochet@malvoya.app" },
    update: {},
    create: { name: "Sarah Miller", email: "sarah.crochet@malvoya.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  const vendor2 = await prisma.user.upsert({
    where: { email: "leo.vintage@malvoya.app" },
    update: {},
    create: { name: "Leo Rossi", email: "leo.vintage@malvoya.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  const vendor3 = await prisma.user.upsert({
    where: { email: "elena.green@malvoya.app" },
    update: {},
    create: { name: "Elena K.", email: "elena.green@malvoya.app", passwordHash: vendorHash, role: "VENDOR" },
  });

  // Stores
  const store1 = await prisma.store.upsert({
    where: { ownerId: vendor1.id },
    update: {},
    create: {
      ownerId: vendor1.id, name: "Sarah's Crochet Studio", category: "HANDMADE",
      description: "Beautifully handcrafted crochet bags and accessories made with organic cotton.",
      isVerified: true, isEcoFriendly: true, isHomeBased: true,
      address: "Munkkiniemi, Helsinki", latitude: 60.198, longitude: 24.878,
      rating: 5.0, totalReviews: 42,
    },
  });

  const store2 = await prisma.store.upsert({
    where: { ownerId: vendor2.id },
    update: {},
    create: {
      ownerId: vendor2.id, name: "Leo's Retro Finds", category: "THRIFT",
      description: "A curated collection of 90s streetwear and vintage denim from my personal archive.",
      isVerified: true, isEcoFriendly: true, isHomeBased: true,
      address: "Kallio, Helsinki", latitude: 60.184, longitude: 24.951,
      rating: 4.8, totalReviews: 128,
    },
  });

  const store3 = await prisma.store.upsert({
    where: { ownerId: vendor3.id },
    update: {},
    create: {
      ownerId: vendor3.id, name: "Elena's Eco Home", category: "HOME_DECOR",
      description: "Sustainable home decor items made from recycled materials and natural wood.",
      isVerified: true, isEcoFriendly: true, isHomeBased: true,
      address: "Töölö, Helsinki", latitude: 60.178, longitude: 24.925,
      rating: 4.9, totalReviews: 56,
    },
  });

  // Products
  await prisma.product.createMany({
    skipDuplicates: true,
    data: [
      // Sarah's Crochet - Handmade
      { storeId: store1.id, name: "Ocean Breeze Tote Bag", category: "Bags", condition: "NEW", canBeSold: true, salePriceCents: 4500, canBeRented: false, stockQuantity: 2, isEcoFriendly: true, isHandmade: true, images: ["https://images.unsplash.com/photo-1544816155-12df9643f363?w=800"] },
      { storeId: store1.id, name: "Hand-Knitted Summer Hat", category: "Accessories", condition: "NEW", canBeSold: true, salePriceCents: 2500, canBeRented: false, stockQuantity: 3, isHandmade: true, images: ["https://images.unsplash.com/photo-1572307480813-ceb0e59d8325?w=800"] },

      // Leo's Retro Finds - Thrift
      { storeId: store2.id, name: "Vintage 1994 Denim Jacket", category: "Clothing", condition: "GOOD", canBeSold: true, salePriceCents: 7500, canBeRented: true, rentalDayCents: 1500, depositCents: 4000, stockQuantity: 1, isSecondHand: true, isEcoFriendly: true, images: ["https://images.unsplash.com/photo-1551537482-f2075a1d41f2?w=800"] },
      { storeId: store2.id, name: "Retro Graphic Band Tee", category: "Clothing", condition: "FAIR", canBeSold: true, salePriceCents: 3000, stockQuantity: 1, isSecondHand: true, images: ["https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=800"] },

      // Elena's Eco Home - Decor
      { storeId: store3.id, name: "Recycled Glass Candle Holder", category: "Decor", condition: "NEW", canBeSold: true, salePriceCents: 1800, stockQuantity: 10, isEcoFriendly: true, isHandmade: true, images: ["https://images.unsplash.com/photo-1505944270255-bd2b896e7518?w=800"] },
      { storeId: store3.id, name: "Driftwood Wall Hanging", category: "Art", condition: "NEW", canBeSold: true, salePriceCents: 5500, stockQuantity: 1, isEcoFriendly: true, isHandmade: true, images: ["https://images.unsplash.com/photo-1513519245088-0e12902e35ca?w=800"] },
    ],
  });

  // Couriers
  await prisma.courier.createMany({
    skipDuplicates: true,
    data: [
      { name: "Mikael K.", phone: "+358401234567", isActive: true, latitude: 60.170, longitude: 24.940 },
      { name: "Aisha R.",  phone: "+358409876543", isActive: true, latitude: 60.175, longitude: 24.955 },
    ],
  });

  // Test customer
  const customerHash = await bcrypt.hash("Customer1234!", 12);
  await prisma.user.upsert({
    where: { email: "customer@malvoya.app" },
    update: {},
    create: { name: "Community User", email: "customer@malvoya.app", passwordHash: customerHash, role: "CUSTOMER" },
  });

  console.log("✅ Malvoya Seed complete!");
  console.log("  admin@malvoya.app     / Admin1234!");
  console.log("  customer@malvoya.app  / Customer1234!");
}

main().catch(console.error).finally(() => prisma.$disconnect());
