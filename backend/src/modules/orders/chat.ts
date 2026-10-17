import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { auth, AuthRequest } from "../../middleware/auth";
import { getIo } from "../../lib/socket";
import { Actor, getOrderRelation, OrderRelation } from "./access";

/**
 * Order chat between the customer and the assigned courier (an admin can read along). Messages are stored so a
 * conversation survives a lost connection, and deleted 30 days after the order is completed or cancelled.
 * The socket (chat:send) and HTTP (POST /orders/:id/messages, for when the socket is down) share these rules.
 */
export const MAX_MESSAGE_LENGTH = 1000;
const HISTORY_LIMIT = 100;
const RETENTION_DAYS = 30;
const MESSAGES_PER_MINUTE = 30;
const CHAT_RELATIONS: OrderRelation[] = ["customer", "courier", "admin"];
const CLOSED = ["DELIVERED", "CANCELLED", "REFUNDED"];

export type ChatMessage = { id: number; orderId: number; senderRole: string; senderId: number; text: string; createdAt: Date };
const messageSelect = { id: true, orderId: true, senderRole: true, senderId: true, text: true, createdAt: true } as const;

/** May this user read the order's chat? (customer, assigned courier, admin) */
export async function canReadChat(orderId: number, actor: Actor) {
  const relation = await getOrderRelation(orderId, actor);
  return !!relation && CHAT_RELATIONS.includes(relation);
}

export async function chatHistory(orderId: number): Promise<ChatMessage[]> {
  const rows = await prisma.orderMessage.findMany({ where: { orderId }, select: messageSelect, orderBy: { id: "desc" }, take: HISTORY_LIMIT });
  return rows.reverse();
}

/** Stores a message and sends it to everyone in the order's chat room. Throws ApiError when it may not be sent. */
export async function postMessage(orderId: number, actor: Actor, rawText: string, senderLabel?: string): Promise<ChatMessage> {
  const relation = await getOrderRelation(orderId, actor);
  if (!relation || !CHAT_RELATIONS.includes(relation)) throw new ApiError("Order not found", 404);
  const text = rawText.trim().slice(0, MAX_MESSAGE_LENGTH);
  if (!text) throw new ApiError("Write a message first", 400);
  const order = await prisma.order.findUnique({ where: { id: orderId }, select: { status: true, courierId: true } });
  if (!order || CLOSED.includes(order.status)) throw new ApiError("This order is closed, so its chat is closed too", 409);
  const recent = await prisma.orderMessage.count({ where: { orderId, senderId: actor.id, createdAt: { gte: new Date(Date.now() - 60_000) } } });
  if (recent >= MESSAGES_PER_MINUTE) throw new ApiError("You are sending messages very fast. Please wait a moment.", 429);

  const message = await prisma.orderMessage.create({ data: { orderId, senderRole: actor.role, senderId: actor.id, text }, select: messageSelect });
  // Same event as before, plus the stored message's id and fields
  getIo()?.to(`chat:${orderId}`).emit("chat:message", {
    ...message,
    role: actor.role,
    sender: senderLabel?.slice(0, 60) || actor.role,
    timestamp: message.createdAt.toISOString(),
  });
  return message;
}

/** Messages of orders completed or cancelled more than 30 days ago are deleted (scheduler job "chat-purge"). */
export async function purgeOldMessages() {
  const before = new Date(Date.now() - RETENTION_DAYS * 86_400_000);
  const res = await prisma.orderMessage.deleteMany({
    where: { order: { OR: [{ deliveredAt: { lt: before } }, { cancelledAt: { lt: before } }] } },
  });
  return res.count;
}

export const chatRoutes = Router();

chatRoutes.get("/orders/:id(\\d+)/messages", auth, async (req: AuthRequest, res: Response) => {
  const orderId = positiveId(req.params.id)!;
  try {
    if (!(await canReadChat(orderId, req.user!))) throw new ApiError("Order not found", 404);
    res.json({ ok: true, messages: await chatHistory(orderId) });
  } catch (e) { sendError(res, e); }
});

chatRoutes.post("/orders/:id(\\d+)/messages", auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ text: z.string().max(5000) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Write a message first" });
  try {
    res.status(201).json({ ok: true, message: await postMessage(positiveId(req.params.id)!, req.user!, body.data.text) });
  } catch (e) { sendError(res, e); }
});
