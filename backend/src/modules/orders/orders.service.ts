import { prisma } from "../../lib/prisma";
import { assignmentQueue } from "../../lib/queue";
import { calcOrderPricing, calcRentalPricing } from "../../utils/pricing";
import { env } from "../../config/env";
import Stripe from "stripe";

const stripe = new Stripe(env.stripeSecretKey, { apiVersion: "2023-10-16" as any });

// ─── ORDERS (SALE) ──────────────────────────────────────────────────────────

export async function createOrder(userId: number, input: {
  storeId: number; deliveryAddress: string; deliveryLat?: number;
  deliveryLng?: number; notes?: string;
  items: { productId: number; variantId?: number; quantity: number }[];
}) {
  // 1. Load & validate all products
  const productIds = input.items.map(i => i.productId);
  const products   = await prisma.product.findMany({ where: { id: { in: productIds } } });

  let subtotalCents = 0;
  const itemsData: any[] = [];

  for (const item of input.items) {
    const product = products.find(p => p.id === item.productId);
    if (!product)          throw new Error(`Product ${item.productId} not found`);
    if (!product.canBeSold) throw new Error(`Product ${product.name} is not for sale`);
    if (!product.isAvailable || product.stockQuantity < item.quantity)
      throw new Error(`Insufficient stock for ${product.name}`);

    let unitCents = product.salePriceCents!;
    if (item.variantId) {
      const variant = await prisma.productVariant.findUniqueOrThrow({ where: { id: item.variantId } });
      unitCents += variant.priceAdjustCents;
      if (variant.stock < item.quantity) throw new Error(`Variant out of stock`);
    }
    subtotalCents += unitCents * item.quantity;
    itemsData.push({ productId: item.productId, variantId: item.variantId, quantity: item.quantity, unitCents });
  }

  const pricing = calcOrderPricing(subtotalCents);

  // 2. Create Stripe PaymentIntent
  const paymentIntent = await stripe.paymentIntents.create({
    amount:   pricing.totalCents,
    currency: "usd",
    metadata: { userId: String(userId), storeId: String(input.storeId) },
  });

  // 3. Create order + items in a transaction
  const order = await prisma.$transaction(async (tx) => {
    const order = await tx.order.create({
      data: {
        userId, storeId: input.storeId,
        deliveryAddress: input.deliveryAddress,
        deliveryLat: input.deliveryLat, deliveryLng: input.deliveryLng,
        notes: input.notes,
        ...pricing,
        stripePaymentIntentId: paymentIntent.id,
        items: { createMany: { data: itemsData } },
      },
      include: { items: true },
    });

    // 4. Decrement stock
    for (const item of input.items) {
      await tx.product.update({
        where: { id: item.productId },
        data:  { stockQuantity: { decrement: item.quantity } },
      });
    }
    return order;
  });

  // 5. Queue courier assignment
  await assignmentQueue.add("assign-delivery", { orderId: order.id, type: "ORDER" });

  return { order, clientSecret: paymentIntent.client_secret };
}

export async function getOrder(id: number, userId: number) {
  const order = await prisma.order.findUniqueOrThrow({
    where: { id },
    include: { items: { include: { product: true } }, courier: true, store: true },
  });
  if (order.userId !== userId) throw new Error("Forbidden");
  return order;
}

export async function listOrders(userId: number) {
  return prisma.order.findMany({
    where: { userId },
    include: { items: { include: { product: { select: { name: true, images: true } } } }, store: { select: { name: true, logoUrl: true } } },
    orderBy: { createdAt: "desc" },
  });
}

// ─── RENTALS ─────────────────────────────────────────────────────────────────

export async function createRental(userId: number, input: {
  startDate: string; endDate: string; deliveryAddress: string;
  items: { productId: number; variantId?: number; quantity: number }[];
}) {
  const start = new Date(input.startDate);
  const end   = new Date(input.endDate);
  const days  = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));

  const productIds = input.items.map(i => i.productId);
  const products   = await prisma.product.findMany({ where: { id: { in: productIds } } });

  let totalSubCents = 0; let totalDepositCents = 0;
  const itemsData: any[] = [];

  for (const item of input.items) {
    const product = products.find(p => p.id === item.productId);
    if (!product)            throw new Error(`Product ${item.productId} not found`);
    if (!product.canBeRented) throw new Error(`${product.name} is not available for rent`);
    if (!product.isAvailable) throw new Error(`${product.name} is not available`);

    // Check no overlapping rental for this product
    const conflict = await prisma.rentalItem.findFirst({
      where: {
        productId: item.productId,
        rental: { status: { in: ["PENDING","CONFIRMED","ACTIVE"] }, startDate: { lt: end }, endDate: { gt: start } },
      },
    });
    if (conflict) throw new Error(`${product.name} is already rented for those dates`);

    const pricing = calcRentalPricing(product.rentalDayCents!, item.quantity, days, product.depositCents!);
    totalSubCents     += pricing.subtotalCents;
    totalDepositCents += pricing.depositCents;
    itemsData.push({ productId: item.productId, variantId: item.variantId, quantity: item.quantity, dailyCents: product.rentalDayCents! });
  }

  const commissionCents  = Math.round(totalSubCents * env.commissionRate);
  const deliveryFeeCents = env.deliveryFeeCents;
  const totalCents       = totalSubCents + totalDepositCents + deliveryFeeCents;

  const paymentIntent = await stripe.paymentIntents.create({
    amount: totalCents, currency: "usd",
    metadata: { userId: String(userId), type: "RENTAL" },
  });

  const rental = await prisma.rental.create({
    data: {
      userId, startDate: start, endDate: end, rentalDays: days,
      subtotalCents: totalSubCents, depositCents: totalDepositCents,
      commissionCents, deliveryFeeCents, totalCents,
      stripePaymentIntentId: paymentIntent.id,
      items: { createMany: { data: itemsData } },
    },
    include: { items: true },
  });

  await assignmentQueue.add("assign-delivery", { rentalId: rental.id, type: "RENTAL" });
  return { rental, clientSecret: paymentIntent.client_secret };
}

export async function getRental(id: number, userId: number) {
  const rental = await prisma.rental.findUniqueOrThrow({
    where: { id },
    include: { items: { include: { product: true } }, courier: true },
  });
  if (rental.userId !== userId) throw new Error("Forbidden");
  return rental;
}

export async function listRentals(userId: number) {
  return prisma.rental.findMany({
    where: { userId },
    include: { items: { include: { product: { select: { name: true, images: true } } } } },
    orderBy: { createdAt: "desc" },
  });
}

// ─── RETURNS ─────────────────────────────────────────────────────────────────

export async function createReturn(userId: number, input: {
  orderId?: number; rentalId?: number; reason: string; conditionNote?: string;
}) {
  if (input.orderId) {
    const order = await prisma.order.findUniqueOrThrow({ where: { id: input.orderId } });
    if (order.userId !== userId) throw new Error("Forbidden");
    if (order.status !== "DELIVERED") throw new Error("Order must be delivered before returning");
    const windowMs = env.returnWindowDays * 24 * 60 * 60 * 1000;
    if (Date.now() - order.updatedAt.getTime() > windowMs)
      throw new Error(`Return window of ${env.returnWindowDays} days has passed`);
  }

  if (input.rentalId) {
    const rental = await prisma.rental.findUniqueOrThrow({ where: { id: input.rentalId } });
    if (rental.userId !== userId) throw new Error("Forbidden");
    if (!["ACTIVE","OVERDUE"].includes(rental.status))
      throw new Error("Rental must be active to initiate return");
  }

  const ret = await prisma.return.create({
    data: { userId, orderId: input.orderId, rentalId: input.rentalId, reason: input.reason as any, conditionNote: input.conditionNote },
  });

  await assignmentQueue.add("assign-return", { returnId: ret.id });
  return ret;
}

export async function updateReturnStatus(id: number, data: {
  status: string; conditionNote?: string; refundCents?: number; damageDedCents?: number;
}) {
  return prisma.return.update({ where: { id }, data: data as any });
}

export async function getReturn(id: number, userId: number) {
  const ret = await prisma.return.findUniqueOrThrow({ where: { id } });
  if (ret.userId !== userId) throw new Error("Forbidden");
  return ret;
}
