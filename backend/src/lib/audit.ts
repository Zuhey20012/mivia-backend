import pino from "pino";
import { Prisma } from "@prisma/client";
import { prisma } from "./prisma";

const logger = pino({ name: "audit" });

/**
 * One way to write the admin audit log (since 2.16.0): who did what to which record, with the value before and after.
 * Bans, approvals, suspensions, promo changes, refunds, order actions, DAC7 report views and switches all go here.
 * Never throws: a failed audit write is logged, the admin action itself has already happened.
 */
export async function audit(
  adminId: number, action: string, entity: string, entityId: number,
  values: { oldValue?: unknown; newValue?: unknown } = {},
) {
  try {
    return await prisma.adminAuditLog.create({
      data: {
        adminId, action, entity, entityId,
        ...(values.oldValue !== undefined ? { oldValue: values.oldValue as Prisma.InputJsonValue } : {}),
        ...(values.newValue !== undefined ? { newValue: values.newValue as Prisma.InputJsonValue } : {}),
      },
    });
  } catch (e: any) {
    logger.error({ action, entity, entityId, err: e?.message }, "Audit row not written");
    return null;
  }
}
