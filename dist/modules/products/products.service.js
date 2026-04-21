"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getProductsByStore = getProductsByStore;
exports.getProductById = getProductById;
exports.createProduct = createProduct;
exports.updateProduct = updateProduct;
exports.deleteProduct = deleteProduct;
exports.addProductImages = addProductImages;
const prisma_1 = require("../../lib/prisma");
async function getProductsByStore(storeId, query) {
    const page = Math.max(1, Number(query.page || 1));
    const limit = Math.min(50, Math.max(1, Number(query.limit || 20)));
    const where = { storeId, isAvailable: true };
    if (query.canBeSold)
        where.canBeSold = query.canBeSold === "true";
    if (query.canBeRented)
        where.canBeRented = query.canBeRented === "true";
    if (query.isEcoFriendly)
        where.isEcoFriendly = query.isEcoFriendly === "true";
    if (query.isSecondHand)
        where.isSecondHand = query.isSecondHand === "true";
    if (query.condition)
        where.condition = query.condition;
    if (query.search)
        where.name = { contains: query.search, mode: "insensitive" };
    if (query.minPrice || query.maxPrice) {
        where.salePriceCents = {};
        if (query.minPrice)
            where.salePriceCents.gte = Number(query.minPrice);
        if (query.maxPrice)
            where.salePriceCents.lte = Number(query.maxPrice);
    }
    const [products, total] = await Promise.all([
        prisma_1.prisma.product.findMany({
            where, skip: (page - 1) * limit, take: limit,
            include: { variants: true },
            orderBy: [{ isFeatured: "desc" }, { createdAt: "desc" }],
        }),
        prisma_1.prisma.product.count({ where }),
    ]);
    return { products, total, page, limit };
}
async function getProductById(id) {
    return prisma_1.prisma.product.findUniqueOrThrow({
        where: { id },
        include: { variants: true, store: { select: { id: true, name: true, logoUrl: true, rating: true } } },
    });
}
async function createProduct(storeId, data) {
    const { variants, ...productData } = data;
    return prisma_1.prisma.product.create({
        data: {
            ...productData, storeId,
            variants: variants?.length ? { createMany: { data: variants } } : undefined,
        },
        include: { variants: true },
    });
}
async function updateProduct(id, vendorId, data) {
    const product = await prisma_1.prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
    if (product.store.ownerId !== vendorId)
        throw new Error("Forbidden");
    const { variants, ...productData } = data;
    return prisma_1.prisma.product.update({ where: { id }, data: productData, include: { variants: true } });
}
async function deleteProduct(id, vendorId) {
    const product = await prisma_1.prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
    if (product.store.ownerId !== vendorId)
        throw new Error("Forbidden");
    await prisma_1.prisma.product.update({ where: { id }, data: { isAvailable: false } });
}
async function addProductImages(id, vendorId, imageUrls) {
    const product = await prisma_1.prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
    if (product.store.ownerId !== vendorId)
        throw new Error("Forbidden");
    const images = [...product.images, ...imageUrls];
    return prisma_1.prisma.product.update({ where: { id }, data: { images } });
}
