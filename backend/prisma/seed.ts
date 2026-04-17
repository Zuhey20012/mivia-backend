import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    await prisma.order.deleteMany();
    await prisma.rental.deleteMany();
    await prisma.variant.deleteMany();
    await prisma.product.deleteMany();
    await prisma.vendor.deleteMany();
    await prisma.courier.deleteMany();

    const v1 = await prisma.vendor.create({ data: { name: 'Local Boutique', rating: 4.8 } });
    const v2 = await prisma.vendor.create({ data: { name: 'Eco Seller', rating: 4.6 } });

    const p1 = await prisma.product.create({
        data: {
            name: 'Jacket — Lightweight',
            category: 'Apparel',
            subCategory: 'Jacket',
            price: 79.99,
            vendorId: v1.id,
            ecoFriendly: true,
            description: 'Generic lightweight jacket.',
            variants: { create: [{ sku: 'JKT-001-S', size: 'S', stock: 10 }, { sku: 'JKT-001-M', size: 'M', stock: 8 }] }
        }
    });

    const p2 = await prisma.product.create({
        data: {
            name: 'Face Cream 50ml',
            category: 'Beauty',
            subCategory: 'Face Cream',
            price: 24.99,
            vendorId: v2.id,
            sampleAvailable: true,
            description: 'Hydrating face cream for all skin types.',
            variants: { create: [{ sku: 'CRM-001-50', volumeMl: 50, stock: 20 }] }
        }
    });

    await prisma.courier.createMany({
        data: [
            { name: 'Aisha', status: 'available' },
            { name: 'Leo', status: 'available' },
            { name: 'Mika', status: 'offline' }
        ]
    });

    console.log('Seed complete');
}

main()
    .catch(e => { console.error(e); process.exit(1); })
    .finally(async () => { await prisma.$disconnect(); });
