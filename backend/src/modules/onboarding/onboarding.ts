import pino from "pino";
import { prisma } from "../../lib/prisma";
import { pushToUsers } from "../../lib/push";
import { sendEmail, escapeHtml } from "../../services/notificationDeliveryService";
import { taxInfoComplete, taxRowSelect } from "../sellers/taxInfo";
import { legalState } from "../legal/legalDocs";
import { businessCheckOf } from "../stores/businessCheck";

const logger = pino({ name: "onboarding" });

/**
 * Onboarding checklists from the server (since 2.11.0): GET /stores/my/onboarding and GET /courier/me/onboarding.
 * Each step says whether it is done and which screen the app should open (`action`). When every step except the
 * admin's approval is done, the admins are told once (push + email) and System → attention lists it as
 * "ready for approval". Nothing here approves anyone.
 */
type Step = { key: string; done: boolean; title: { en: string; fi: string }; action: string; status?: string | null; skipped?: boolean };

function summary(steps: Step[], approved: boolean, approvalKey?: string) {
  const done = steps.filter((s) => s.done).length;
  const beforeApproval = steps.filter((s) => s.key !== approvalKey);
  return {
    steps,
    percent: steps.length ? Math.round((done / steps.length) * 100) : 0,
    approved,
    readyForApproval: !approved && beforeApproval.every((s) => s.done),
  };
}

/** The agreement step: the version in force accepted and (since 2.16.0) the "18 or older" confirmation given. */
async function acceptedCurrent(userId: number, doc: "seller-terms" | "courier-agreement") {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { ageConfirmedAt: true } });
  if (!user?.ageConfirmedAt) return false;
  const { current } = await legalState(doc);
  if (!current) return true; // no text on the server: nothing to accept
  return !!(await prisma.agreementAcceptance.findUnique({ where: { userId_doc_version: { userId, doc, version: current.version } }, select: { id: true } }));
}

export async function storeOnboarding(userId: number) {
  const store = await prisma.store.findUnique({
    where: { ownerId: userId },
    include: { taxInfo: { select: taxRowSelect }, _count: { select: { products: { where: { deletedAt: null } } } } },
  });
  const agreement = await acceptedCurrent(userId, "seller-terms");
  if (!store) {
    const steps: Step[] = [
      { key: "details", done: false, title: { en: "Store details", fi: "Kaupan tiedot" }, action: "create_store" },
      { key: "map_pin", done: false, title: { en: "Location on the map", fi: "Sijainti kartalla" }, action: "set_location" },
      { key: "hours", done: false, title: { en: "Opening hours", fi: "Aukioloajat" }, action: "set_hours" },
      { key: "payouts", done: false, title: { en: "Payouts (Stripe)", fi: "Tilitykset (Stripe)" }, action: "connect_payouts" },
      { key: "first_product", done: false, title: { en: "First product", fi: "Ensimmäinen tuote" }, action: "add_product" },
      { key: "tax_info", done: false, title: { en: "Tax details (DAC7)", fi: "Verotiedot (DAC7)" }, action: "tax_info" },
      { key: "agreement", done: agreement, title: { en: "Seller Terms", fi: "Myyjän ehdot" }, action: "accept_agreement" },
      { key: "safety_pledge", done: false, title: { en: "Product safety pledge", fi: "Tuoteturvallisuussitoumus" }, action: "safety_pledge" },
      { key: "business_check", done: false, title: { en: "Business ID check", fi: "Y-tunnuksen tarkistus" }, action: "create_store" },
    ];
    return { store: null, ...summary(steps, false) };
  }
  const check = businessCheckOf(store);
  const businessDone = !check.required || check.verificationStatus === "matched" || check.verificationStatus === "name_mismatch";
  const steps: Step[] = [
    { key: "details", done: !!(store.name && store.address && (store.phone || store.email)), title: { en: "Store details", fi: "Kaupan tiedot" }, action: "edit_store" },
    { key: "map_pin", done: store.latitude !== null && store.longitude !== null, title: { en: "Location on the map", fi: "Sijainti kartalla" }, action: "set_location" },
    { key: "hours", done: store.openingHours !== null, title: { en: "Opening hours", fi: "Aukioloajat" }, action: "set_hours" },
    { key: "payouts", done: store.payoutsEnabled, title: { en: "Payouts (Stripe)", fi: "Tilitykset (Stripe)" }, action: "connect_payouts" },
    { key: "first_product", done: store._count.products > 0, title: { en: "First product", fi: "Ensimmäinen tuote" }, action: "add_product" },
    { key: "tax_info", done: taxInfoComplete(store, store.taxInfo), title: { en: "Tax details (DAC7)", fi: "Verotiedot (DAC7)" }, action: "tax_info" },
    { key: "agreement", done: agreement, title: { en: "Seller Terms", fi: "Myyjän ehdot" }, action: "accept_agreement" },
    // GPSR Art. 22(10)(b) self-certification, once (2.12): POST /stores/my/safety-pledge
    { key: "safety_pledge", done: !!store.safetyPledgeAt, title: { en: "Product safety pledge", fi: "Tuoteturvallisuussitoumus" }, action: "safety_pledge" },
    {
      key: "business_check", done: businessDone, title: { en: "Business ID check", fi: "Y-tunnuksen tarkistus" },
      // not_found / inactive / unavailable: the store fixes its Y-tunnus or waits for the registry; null = not checked yet
      action: !check.required ? "none" : check.verificationStatus === "unavailable" || check.verificationStatus === null ? "wait" : "edit_business_id",
      status: check.verificationStatus, ...(check.required ? {} : { skipped: true }),
    },
  ];
  return { store: { id: store.id, name: store.name }, ...summary(steps, store.isVerified) };
}

export async function courierOnboarding(userId: number) {
  const [user, courier] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { name: true, phone: true } }),
    prisma.courier.findUnique({ where: { userId } }),
  ]);
  const agreement = await acceptedCurrent(userId, "courier-agreement");
  const steps: Step[] = [
    { key: "profile", done: !!(user?.name?.trim() && (courier?.phone || user?.phone)), title: { en: "Name and phone", fi: "Nimi ja puhelin" }, action: "edit_profile" },
    { key: "vehicle", done: !!courier?.vehicleType, title: { en: "Vehicle", fi: "Kulkuneuvo" }, action: "set_vehicle" },
    { key: "payouts", done: !!courier?.payoutsEnabled, title: { en: "Payouts (Stripe)", fi: "Tilitykset (Stripe)" }, action: "connect_payouts" },
    { key: "agreement", done: agreement, title: { en: "Courier Agreement", fi: "Lähettisopimus" }, action: "accept_agreement" },
    { key: "location_disclosure", done: !!courier?.locationDisclosureAt, title: { en: "How your location is used", fi: "Miten sijaintiasi käytetään" }, action: "location_disclosure" },
    { key: "approved", done: !!courier?.isApproved, title: { en: "Approved by Malvoya", fi: "Malvoyan hyväksymä" }, action: "wait_for_approval" },
  ];
  return { courier: courier ? { id: courier.id, vehicleType: courier.vehicleType, locationDisclosureAt: courier.locationDisclosureAt } : null, ...summary(steps, !!courier?.isApproved, "approved") };
}

async function tellAdmins(what: string, path: string) {
  const admins = await prisma.user.findMany({ where: { role: "ADMIN", isActive: true, deletedAt: null }, select: { id: true, email: true }, take: 50 });
  if (!admins.length) return;
  await pushToUsers(admins.map((a) => a.id), { title: "Ready for approval", body: what, data: { type: "ready_for_approval" } }).catch(() => {});
  for (const a of admins) {
    await sendEmail(a.email, `Malvoya – ${what}`, `<p>${escapeHtml(what)}</p><p>Admin panel → ${escapeHtml(path)}</p>`, `${what}\nAdmin panel → ${path}`, { kind: "internal" }).catch(() => {});
  }
}

/** Sets readyForApprovalAt once, when everything but approval is done, and tells the admins that one time. */
export async function checkReadyForApproval(userId: number, role: string) {
  try {
    if (role === "VENDOR") {
      const o = await storeOnboarding(userId);
      if (!o.store || !o.readyForApproval) return false;
      const set = await prisma.store.updateMany({ where: { id: o.store.id, readyForApprovalAt: null, isVerified: false }, data: { readyForApprovalAt: new Date() } });
      if (set.count) await tellAdmins(`Store "${o.store.name}" (#${o.store.id}) has finished onboarding and is ready for approval.`, "Vendors");
      return set.count > 0;
    }
    if (role === "COURIER") {
      const o = await courierOnboarding(userId);
      if (!o.courier || !o.readyForApproval) return false;
      const set = await prisma.courier.updateMany({ where: { id: o.courier.id, readyForApprovalAt: null, isApproved: false }, data: { readyForApprovalAt: new Date() } });
      if (set.count) {
        const c = await prisma.courier.findUnique({ where: { id: o.courier.id }, select: { name: true } });
        await tellAdmins(`Courier "${c?.name ?? ""}" (#${o.courier.id}) has finished onboarding and is ready for approval.`, "Couriers");
      }
      return set.count > 0;
    }
  } catch (e: any) {
    logger.warn({ err: e?.message }, "Ready-for-approval check failed");
  }
  return false;
}

/** System → attention: stores and couriers that finished onboarding and wait for an admin. */
export async function readyForApprovalList() {
  const [stores, couriers] = await Promise.all([
    prisma.store.findMany({ where: { isVerified: false, readyForApprovalAt: { not: null } }, select: { id: true, name: true, readyForApprovalAt: true }, orderBy: { readyForApprovalAt: "asc" }, take: 20 }),
    prisma.courier.findMany({ where: { isApproved: false, readyForApprovalAt: { not: null }, userId: { not: null } }, select: { id: true, name: true, readyForApprovalAt: true }, orderBy: { readyForApprovalAt: "asc" }, take: 20 }),
  ]);
  return { stores, couriers };
}
