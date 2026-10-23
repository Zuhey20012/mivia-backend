import { Prisma } from "@prisma/client";
import { Template } from "./taxonomy";

/**
 * Certification schemes a shop may attach (spec §2.12). Only schemes on this fixed list; a scheme is added only after an
 * admin has confirmed it is a real certification scheme (third-party verified, open, with sanctions) or set by a public
 * authority (AB §5). The chip on the product page names the scheme and the licence number itself, never behind a link.
 */
type L = { en: string; fi: string };
type Group = "textile" | "footwear" | "bags" | "cosmetics" | "any";

export const SCHEMES: Record<string, { name: L; for: Group[] }> = {
  eu_ecolabel: { name: { en: "EU Ecolabel", fi: "EU-ympäristömerkki" }, for: ["textile", "footwear", "cosmetics"] },
  nordic_swan: { name: { en: "Nordic Swan Ecolabel", fi: "Joutsenmerkki" }, for: ["textile", "cosmetics"] },
  gots: { name: { en: "GOTS (organic)", fi: "GOTS (luomu)" }, for: ["textile"] },
  ocs: { name: { en: "Organic Content Standard", fi: "OCS" }, for: ["textile"] },
  grs: { name: { en: "Global Recycled Standard", fi: "GRS" }, for: ["textile", "footwear", "bags"] },
  rcs: { name: { en: "Recycled Claim Standard", fi: "RCS" }, for: ["textile", "footwear", "bags"] },
  oeko_tex_100: { name: { en: "OEKO-TEX Standard 100", fi: "OEKO-TEX Standard 100" }, for: ["textile"] },
  bluesign: { name: { en: "bluesign", fi: "bluesign" }, for: ["textile"] },
  rws: { name: { en: "Responsible Wool Standard", fi: "RWS" }, for: ["textile"] },
  rds: { name: { en: "Responsible Down Standard", fi: "RDS" }, for: ["textile"] },
  fsc: { name: { en: "FSC", fi: "FSC" }, for: ["any"] },
  fairtrade: { name: { en: "Fairtrade", fi: "Reilu kauppa" }, for: ["any"] },
  leaping_bunny: { name: { en: "Leaping Bunny", fi: "Leaping Bunny" }, for: ["cosmetics"] },
  vegan_society: { name: { en: "The Vegan Society trademark", fi: "Vegan Society -merkki" }, for: ["cosmetics", "footwear", "bags"] },
  cosmos: { name: { en: "COSMOS Organic / Natural", fi: "COSMOS" }, for: ["cosmetics"] },
  natrue: { name: { en: "NATRUE", fi: "NATRUE" }, for: ["cosmetics"] },
  avainlippu: { name: { en: "Key Flag (Avainlippu)", fi: "Avainlippu" }, for: ["any"] },
};
export const SCHEME_KEYS = Object.keys(SCHEMES) as [string, ...string[]];

const GROUP_OF: Record<Template, Group> = {
  APPAREL: "textile", APPAREL_ACCESSORY: "textile", FOOTWEAR: "footwear", BAG: "bags", ACCESSORY: "bags",
  EYEWEAR: "any", WATCH: "any", JEWELLERY: "any", BEAUTY_TOOL: "any", HAIR_TOOL: "any",
  COSMETIC_MAKEUP: "cosmetics", COSMETIC_SKIN: "cosmetics", COSMETIC_HAIR: "cosmetics", COSMETIC_NAIL: "cosmetics", FRAGRANCE: "cosmetics",
};

/** Whether a scheme can certify products of this template (e.g. Leaping Bunny only cosmetics). */
export function schemeFits(scheme: string, template: Template | null) {
  const s = SCHEMES[scheme];
  if (!s) return false;
  if (!template || s.for.includes("any")) return true;
  return s.for.includes(GROUP_OF[template]);
}

/** Today's date in Finland (validUntil is a calendar date). */
export function todayDate() {
  const d = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Helsinki", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  return new Date(`${d}T00:00:00.000Z`);
}

/** Only these appear to shoppers and in filters: verified by an admin and not expired. */
export function liveCertificateWhere(): Prisma.CertificateWhereInput {
  return { status: "VERIFIED", validUntil: { gte: todayDate() } };
}

type CertRow = {
  id: number; scheme: string; licenceNumber: string; holderName: string; scope: string; componentDescription: string | null;
  validUntil: Date; publicVerifyUrl: string | null; status: string; rejectionReason?: string | null; evidenceUrl?: string;
};

export function isLive(c: { status: string; validUntil: Date }) {
  return c.status === "VERIFIED" && c.validUntil.getTime() >= todayDate().getTime();
}

/** Chip text shown on the page itself: "Joutsenmerkki · lisenssi 1234 5678" (+ scope for components). */
export function presentCertificate(c: CertRow, opts: { owner?: boolean } = {}) {
  const s = SCHEMES[c.scheme];
  const name = s?.name ?? { en: c.scheme, fi: c.scheme };
  const scopeText = c.scope === "component" && c.componentDescription
    ? { en: ` (applies to: ${c.componentDescription})`, fi: ` (koskee: ${c.componentDescription})` }
    : { en: "", fi: "" };
  return {
    id: c.id,
    scheme: c.scheme,
    schemeName: name,
    licenceNumber: c.licenceNumber,
    holderName: c.holderName,
    scope: c.scope,
    componentDescription: c.componentDescription,
    validUntil: c.validUntil.toISOString().slice(0, 10),
    publicVerifyUrl: c.publicVerifyUrl,
    label: { en: `${name.en} · licence ${c.licenceNumber}${scopeText.en}`, fi: `${name.fi} · lisenssi ${c.licenceNumber}${scopeText.fi}` },
    ...(opts.owner ? { status: c.status, live: isLive(c), rejectionReason: c.rejectionReason ?? null, evidenceUrl: c.evidenceUrl } : {}),
  };
}
