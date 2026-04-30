import "dotenv/config";
import { Worker, Job } from "bullmq";
import { PrismaClient } from "@prisma/client";
import { haversineKm, calcEtaMinutes } from "../utils/distance";
import { env } from "../config/env";

const prisma = new PrismaClient();
const MAX_RETRIES = 5;

// ─── Find nearest idle courier ───────────────────────────────────────────────
async function findNearestCourier(storeLat: number, storeLng: number) {
  const couriers = await prisma.courier.findMany({
    where: {
      isActive: true,
      currentOrderId:  null,
      currentRentalId: null,
      currentReturnId: null,
      latitude:  { not: null },
      longitude: { not: null },
    },
  });
  if (!couriers.length) return null;

  return couriers.sort((a, b) =>
    haversineKm(storeLat, storeLng, a.latitude!, a.longitude!) -
    haversineKm(storeLat, storeLng, b.latitude!, b.longitude!)
  )[0];
}

// ─── Assign delivery (order or rental) ──────────────────────────────────────
async function handleAssignDelivery(job: Job) {
  const { orderId, rentalId, type } = job.data as { orderId?: number; rentalId?: number; type: string };

  if (type === "ORDER" && orderId) {
    const order = await prisma.order.findUnique({
      where: { id: orderId }, include: { store: true },
    });
    if (!order || order.status === "CANCELLED") return;

    const storeLat = order.store.latitude ?? 60.17; // fallback Helsinki
    const storeLng = order.store.longitude ?? 24.94;
    const courier = await findNearestCourier(storeLat, storeLng);

    if (!courier) throw new Error(`No courier available for order ${orderId}`); // triggers retry

    const distKm    = order.deliveryLat ? haversineKm(storeLat, storeLng, order.deliveryLat, order.deliveryLng!) : 5;
    const etaMinutes = calcEtaMinutes(distKm);

    await prisma.$transaction([
      prisma.order.update({ where: { id: orderId }, data: { courierId: courier.id, status: "CONFIRMED", etaMinutes } }),
      prisma.courier.update({ where: { id: courier.id }, data: { currentOrderId: orderId } }),
    ]);
    console.log(`[worker] Order ${orderId} assigned to courier ${courier.id}, ETA ${etaMinutes}min`);
  }

  if (type === "RENTAL" && rentalId) {
    const rental = await prisma.rental.findUnique({ where: { id: rentalId } });
    if (!rental || rental.status === "CANCELLED") return;
    const courier = await findNearestCourier(60.17, 24.94); // TODO: use store lat/lng
    if (!courier) throw new Error(`No courier for rental ${rentalId}`);

    await prisma.$transaction([
      prisma.rental.update({ where: { id: rentalId }, data: { courierId: courier.id, status: "CONFIRMED" } }),
      prisma.courier.update({ where: { id: courier.id }, data: { currentRentalId: rentalId } }),
    ]);
    console.log(`[worker] Rental ${rentalId} assigned to courier ${courier.id}`);
  }
}

// ─── Assign return pickup ────────────────────────────────────────────────────
async function handleAssignReturn(job: Job) {
  const { returnId } = job.data as { returnId: number };
  const ret = await prisma.return.findUnique({ where: { id: returnId } });
  if (!ret || ret.status === "REJECTED") return;

  const courier = await findNearestCourier(60.17, 24.94);
  if (!courier) throw new Error(`No courier for return ${returnId}`);

  await prisma.$transaction([
    prisma.return.update({ where: { id: returnId }, data: { courierId: courier.id, status: "APPROVED" } }),
    prisma.courier.update({ where: { id: courier.id }, data: { currentReturnId: returnId } }),
  ]);
  console.log(`[worker] Return ${returnId} pickup assigned to courier ${courier.id}`);
}

// ─── Worker ──────────────────────────────────────────────────────────────────
const redisConnection = { host: new URL(env.redisUrl).hostname, port: Number(new URL(env.redisUrl).port) || 6379 };

const worker = new Worker(
  "assignments",
  async (job: Job) => {
    if (job.name === "assign-delivery") return handleAssignDelivery(job);
    if (job.name === "assign-return")   return handleAssignReturn(job);
  },
  {
    connection: redisConnection,
    settings: {
      backoffStrategies: {
        custom: (attemptsMade: number) => Math.min(attemptsMade * 30_000, 90_000)
      }
    }
  }
);

worker.waitUntilReady().then(() => console.log("[worker] Assignment worker ready"));
worker.on("failed",    (job, err) => console.error(`[worker] Job ${job?.id} failed:`, err?.message));
worker.on("completed", (job)      => console.log(`[worker] Job ${job.id} (${job.name}) completed`));
worker.on("error",     (err)      => console.error("[worker] Worker error:", err));
