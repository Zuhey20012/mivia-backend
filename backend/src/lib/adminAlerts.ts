import pino from "pino";
import { prisma } from "./prisma";
import { pushToUsers } from "./push";
import { sendAdminAlertEmail } from "../services/notificationDeliveryService";

const logger = pino({ name: "admin-alerts" });

/**
 * Tells every active admin at once, by push and email (since 2.17.0): chargebacks, courier incidents, failed payouts
 * and new System attention items (ops-alerts job). Never throws.
 */
export async function alertAdmins(subject: string, lines: string[], data: Record<string, string> = { type: "ops_alert" }) {
  try {
    const admins = await prisma.user.findMany({ where: { role: "ADMIN", isActive: true, deletedAt: null }, select: { id: true, email: true }, take: 50 });
    if (!admins.length) return 0;
    await pushToUsers(admins.map((a) => a.id), { title: subject.slice(0, 100), body: lines.join(" ").slice(0, 200), data }).catch(() => {});
    for (const a of admins) await sendAdminAlertEmail(a.email, subject, lines).catch(() => {});
    return admins.length;
  } catch (e: any) {
    logger.error({ err: e?.message }, "Admin alert not sent");
    return 0;
  }
}
