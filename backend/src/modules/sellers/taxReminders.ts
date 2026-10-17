import pino from "pino";
import { prisma } from "../../lib/prisma";
import { pushToUser } from "../../lib/push";
import { localeOfUser, t } from "../../lib/i18n";
import { sendTaxInfoReminder } from "../../services/notificationDeliveryService";
import { helsinkiInstant, helsinkiParts } from "../../utils/deliverySlots";
import { taxInfoComplete, taxRowSelect } from "./taxInfo";

const logger = pino({ name: "dac7-reminders" });

/** At most one reminder every 30 days, and at most 2 per calendar year. No payout is ever withheld. */
export const TAX_REMINDER_INTERVAL_DAYS = 30;
export const TAX_REMINDERS_PER_YEAR = 2;

/**
 * DAC7: live stores with sales (delivered or collected orders) this year whose tax details are incomplete get a
 * push and an email asking for them (scheduler job "dac7-reminders").
 */
export async function sendTaxInfoReminders(now = new Date()) {
  const year = Number(helsinkiParts(now).date.slice(0, 4));
  const yearStart = helsinkiInstant(`${year}-01-01`, "00:00");
  const due = new Date(now.getTime() - TAX_REMINDER_INTERVAL_DAYS * 86_400_000);
  const stores = await prisma.store.findMany({
    where: {
      isVerified: true,
      orders: { some: { deliveredAt: { gte: yearStart }, status: { in: ["DELIVERED", "REFUNDED"] } } },
      OR: [{ taxReminderAt: null }, { taxReminderAt: { lt: due } }],
    },
    select: {
      id: true, name: true, ownerId: true, sellerType: true, businessId: true, taxReminderCount: true, taxReminderYear: true,
      owner: { select: { email: true } }, taxInfo: { select: taxRowSelect },
    },
    take: 500,
  });
  let sent = 0;
  for (const s of stores) {
    if (taxInfoComplete(s, s.taxInfo)) continue;
    const countThisYear = s.taxReminderYear === year ? s.taxReminderCount : 0;
    if (countThisYear >= TAX_REMINDERS_PER_YEAR) continue;
    // Claim it (several instances never send twice)
    const claimed = await prisma.store.updateMany({
      where: { id: s.id, OR: [{ taxReminderAt: null }, { taxReminderAt: { lt: due } }] },
      data: { taxReminderAt: now, taxReminderCount: countThisYear + 1, taxReminderYear: year },
    });
    if (!claimed.count) continue;
    pushToUser(s.ownerId, {
      title: t("Please add your tax details", "Lisää verotietosi"),
      body: t("You have sales this year: Malvoya must report them to the Tax Administration (DAC7). Open Tax details in the app.",
        "Sinulla on myyntiä tänä vuonna: Malvoyan on ilmoitettava ne Verohallinnolle (DAC7). Avaa sovelluksessa Verotiedot."),
      data: { type: "tax_info" },
    }).catch(() => {});
    sendTaxInfoReminder(s.owner.email, s.name, await localeOfUser(s.ownerId)).catch(() => {});
    sent++;
  }
  if (sent) logger.info({ sent }, "DAC7 tax-detail reminders sent");
  return sent;
}
