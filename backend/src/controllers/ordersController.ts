import { Request, Response } from "express";
import { createOrder } from "../services/ordersService";

export async function createOrderHandler(req: Request, res: Response) {
  try {
    const { userId, vendorId, total } = req.body;
    if (!userId || !vendorId || !total) {
      return res.status(400).json({ ok: false, error: "Missing fields" });
    }
    const order = await createOrder({ userId: Number(userId), vendorId: Number(vendorId), total: Number(total) });
    res.status(201).json({ ok: true, order });
  } catch (e) {
    console.error(e);
    res.status(500).json({ ok: false, error: "Failed to create order" });
  }
}
