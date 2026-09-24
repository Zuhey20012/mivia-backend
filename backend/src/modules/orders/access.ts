import { prisma } from "../../lib/prisma";

export type Actor = { id: number; role: string };
export type OrderRelation = "customer" | "vendor" | "courier" | "admin";

/** Courier profile of a logged-in COURIER user (Courier and User are separate tables). */
export async function getCourierForUser(userId: number) {
  return prisma.courier.findUnique({ where: { userId } });
}

/**
 * Works out how the actor relates to an order. Returns null when they have no business seeing it.
 */
export async function getOrderRelation(orderId: number, actor: Actor): Promise<OrderRelation | null> {
  if (!Number.isInteger(orderId) || orderId <= 0) return null;
  if (actor.role === "ADMIN") return "admin";

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { userId: true, courier: { select: { userId: true } }, store: { select: { ownerId: true } } },
  });
  if (!order) return null;
  if (order.userId === actor.id) return "customer";
  if (actor.role === "VENDOR" && order.store.ownerId === actor.id) return "vendor";
  if (actor.role === "COURIER" && order.courier?.userId === actor.id) return "courier";
  return null;
}

export async function getRentalRelation(rentalId: number, actor: Actor): Promise<"customer" | "courier" | "admin" | null> {
  if (!Number.isInteger(rentalId) || rentalId <= 0) return null;
  if (actor.role === "ADMIN") return "admin";
  const rental = await prisma.rental.findUnique({
    where: { id: rentalId },
    select: { userId: true, courier: { select: { userId: true } } },
  });
  if (!rental) return null;
  if (rental.userId === actor.id) return "customer";
  if (actor.role === "COURIER" && rental.courier?.userId === actor.id) return "courier";
  return null;
}
