"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getStores = getStores;
exports.getStoreById = getStoreById;
exports.createStore = createStore;
exports.updateStore = updateStore;
exports.updateStoreLogo = updateStoreLogo;
const prisma_1 = require("../../lib/prisma");
async function getStores(query) {
    const page = Math.max(1, Number(query.page));
    const limit = Math.min(50, Math.max(1, Number(query.limit)));
    const skip = (page - 1) * limit;
    const where = {};
    if (query.category)
        where.category = query.category;
    if (query.isHomeBased)
        where.isHomeBased = query.isHomeBased === "true";
    if (query.search)
        where.name = { contains: query.search, mode: "insensitive" };
    const [stores, total] = await Promise.all([
        prisma_1.prisma.store.findMany({
            where, skip, take: limit,
            select: {
                id: true, name: true, description: true, category: true,
                logoUrl: true, bannerUrl: true, isHomeBased: true, isEcoFriendly: true,
                isVerified: true, address: true, latitude: true, longitude: true,
                rating: true, totalReviews: true,
            },
            orderBy: [{ rating: "desc" }],
        }),
        prisma_1.prisma.store.count({ where }),
    ]);
    return { stores, total, page, limit, pages: Math.ceil(total / limit) };
}
async function getStoreById(id) {
    return prisma_1.prisma.store.findUniqueOrThrow({
        where: { id },
        include: {
            products: {
                where: { isAvailable: true },
                take: 20,
                orderBy: { isFeatured: "desc" },
            },
        },
    });
}
async function createStore(ownerId, data) {
    const existing = await prisma_1.prisma.store.findUnique({ where: { ownerId } });
    if (existing)
        throw new Error("You already have a store");
    return prisma_1.prisma.store.create({ data: { ...data, ownerId } });
}
async function updateStore(id, ownerId, data) {
    const store = await prisma_1.prisma.store.findUniqueOrThrow({ where: { id } });
    if (store.ownerId !== ownerId)
        throw new Error("Forbidden");
    return prisma_1.prisma.store.update({ where: { id }, data });
}
async function updateStoreLogo(id, ownerId, logoUrl) {
    const store = await prisma_1.prisma.store.findUniqueOrThrow({ where: { id } });
    if (store.ownerId !== ownerId)
        throw new Error("Forbidden");
    return prisma_1.prisma.store.update({ where: { id }, data: { logoUrl } });
}
