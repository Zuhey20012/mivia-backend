import { Router, Request, Response } from "express";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { sendError } from "../../lib/errors";
import { publicCache } from "../../middleware/httpCache";
import { audienceWhere, availableWhere, categoryIndex, isKidsView, registerCountCache, storesInReach } from "./categories";
import { liveCertificateWhere } from "./certificates";
import { BEAUTY_TOPS } from "./taxonomy";

/**
 * Home collections (docs/design/category-sections-v2.md §4): curated rails and tiles that are saved filters, not product
 * types. Each has FI/EN names, an optional active season (months, Europe/Helsinki) and is shown only when it has at
 * least MIN_ITEMS buyable products within delivery reach. Kids views never include beauty or fragrance.
 * GET /collections lists the active ones; GET /products/search?collection=<slug> lists their products.
 */

type L = { en: string; fi: string };
const l = (en: string, fi: string): L => ({ en, fi });

type Def = {
  slug: string;
  group: "season" | "occasion" | "gifts" | "origin" | "certified" | "second_hand" | "brands" | "beauty_concern" | "fit";
  name: L;
  icon: string;
  tileColor: string;
  /** Active months, inclusive (Helsinki); may wrap the year end (10 → 3 = October to March). null = all year */
  months: [number, number] | null;
  /** Beauty collections are never shown in Kids views */
  beauty?: boolean;
  filter: (ids: (slugs: string[]) => number[]) => Prisma.ProductWhereInput;
};

const facet = (key: string, values: string[]): Prisma.ProductWhereInput => ({ facets: { some: { key, value: { in: values } } } });
const GIFT_SLUGS = [
  "makeup-sets", "fragrance-gift-sets", "jewellery-earrings", "jewellery-necklaces", "jewellery-rings", "jewellery-bracelets",
  "jewellery-sets-charms", "jewellery-brooches", "accessories-scarves", "accessories-small", "accessories-hats-beanies",
  "accessories-gloves-mittens", "bags-wallets", "bags-clutches",
];
const gifts = (min: number | null, max: number | null) => (ids: (s: string[]) => number[]): Prisma.ProductWhereInput => ({
  categoryId: { in: ids(GIFT_SLUGS) },
  salePriceCents: { ...(min !== null ? { gte: min } : {}), ...(max !== null ? { lt: max } : {}) },
});

export const COLLECTION_DEFS: Def[] = [
  { slug: "winter-essentials", group: "season", name: l("Winter essentials", "Talven tärkeimmät"), icon: "ac_unit", tileColor: "sand", months: [10, 3],
    filter: (ids) => ({ OR: [facet("season", ["winter"]), facet("linedWarm", ["true"]), { categoryId: { in: ids(["shoes-winter-rubber-boots", "accessories-hats-beanies", "accessories-gloves-mittens", "accessories-scarves", "sport-ski-winter"]) } }] }) },
  { slug: "spring-rain", group: "season", name: l("Spring & rain", "Kevät ja sade"), icon: "umbrella", tileColor: "mint", months: [3, 5],
    filter: (ids) => ({ OR: [facet("season", ["spring"]), facet("waterproof", ["water_repellent", "waterproof_membrane"]), { categoryId: { in: ids(["shoes-rubber-boots", "clothing-outdoor-rainwear"]) } }] }) },
  { slug: "summer", group: "season", name: l("Summer", "Kesä"), icon: "wb_sunny", tileColor: "sunshineLight", months: [5, 8],
    filter: (ids) => ({ OR: [facet("season", ["summer"]), { categoryId: { in: ids(["clothing-swimwear", "shoes-sandals", "accessories-sunglasses", "skincare-sun-selftan"]) } }] }) },
  { slug: "festival-season", group: "season", name: l("Festival season", "Festarit"), icon: "festival", tileColor: "peach", months: [6, 8],
    filter: (ids) => ({ OR: [facet("occasion", ["party", "outdoor"]), { categoryId: { in: ids(["shoes-sandals", "clothing-skirts-shorts", "accessories-sunglasses", "accessories-hats-beanies"]) } }] }) },
  { slug: "party-wedding-guest", group: "occasion", name: l("Party & wedding guest", "Juhliin"), icon: "celebration", tileColor: "lilac", months: null,
    filter: (ids) => ({ OR: [facet("occasion", ["party"]), { categoryId: { in: ids(["clothing-dresses", "clothing-suits-blazers", "clothing-festive-traditional", "shoes-heels", "bags-clutches"]) } }] }) },
  { slug: "work", group: "occasion", name: l("Work", "Töihin"), icon: "work", tileColor: "clay", months: null,
    filter: (ids) => ({ OR: [facet("occasion", ["work"]), { categoryId: { in: ids(["clothing-suits-blazers", "clothing-shirts-blouses", "clothing-workwear"]) } }] }) },
  { slug: "graduation-school-start", group: "occasion", name: l("Graduation & school start", "Valmistujaiset ja koulun alku"), icon: "school", tileColor: "sunshineLight", months: [5, 8],
    filter: (ids) => ({ OR: [facet("occasion", ["party"]), { categoryId: { in: ids(["clothing-festive-traditional", "clothing-dresses", "clothing-suits-blazers", "bags-backpacks"]) } }] }) },
  { slug: "holiday-gifts", group: "gifts", name: l("Holiday gifts", "Joululahjat"), icon: "redeem", tileColor: "peach", months: [11, 12], filter: gifts(null, null) },
  { slug: "gifts-under-25", group: "gifts", name: l("Gifts under 25 €", "Lahjat alle 25 €"), icon: "redeem", tileColor: "lilac", months: null, filter: gifts(null, 2500) },
  { slug: "gifts-25-50", group: "gifts", name: l("Gifts 25–50 €", "Lahjat 25–50 €"), icon: "redeem", tileColor: "mint", months: null, filter: gifts(2500, 5000) },
  { slug: "gifts-50-plus", group: "gifts", name: l("Gifts 50 € and up", "Lahjat yli 50 €"), icon: "redeem", tileColor: "clay", months: null, filter: gifts(5000, null) },
  // Origin claims, only with the seller's declaration (an origin claim, not a sustainability claim)
  { slug: "made-in-finland", group: "origin", name: l("Made in Finland", "Suomessa valmistettu"), icon: "flag", tileColor: "sand", months: null,
    filter: () => facet("madeInFinland", ["true"]) },
  { slug: "handmade", group: "origin", name: l("Handmade", "Käsintehty"), icon: "back_hand", tileColor: "peach", months: null,
    filter: () => ({ isHandmade: true, attributes: { path: ["originDeclared"], equals: true } }) },
  { slug: "certified", group: "certified", name: l("Certified products", "Sertifioidut tuotteet"), icon: "verified", tileColor: "lilac", months: null,
    filter: () => ({ certificates: { some: { certificate: liveCertificateWhere() } } }) },
  { slug: "second-hand-finds", group: "second_hand", name: l("Second-hand finds", "Käytetyt löydöt"), icon: "recycling", tileColor: "sand", months: null,
    filter: () => ({ isSecondHand: true }) },
  { slug: "brands", group: "brands", name: l("Brands A–Z", "Merkit A–Ö"), icon: "sort_by_alpha", tileColor: "clay", months: null,
    filter: () => ({ facets: { some: { key: "brand" } } }) },
  // Beauty by concern: product purpose, not medical claims (Reg. 655/2013)
  { slug: "concern-dry-skin", group: "beauty_concern", name: l("For dry skin", "Kuivalle iholle"), icon: "water_drop", tileColor: "mint", months: null, beauty: true,
    filter: () => facet("skinType", ["dry"]) },
  { slug: "concern-sensitive-skin", group: "beauty_concern", name: l("For sensitive skin", "Herkälle iholle"), icon: "spa", tileColor: "peach", months: null, beauty: true,
    filter: () => facet("skinType", ["sensitive"]) },
  { slug: "concern-blemish-prone", group: "beauty_concern", name: l("For blemish-prone skin", "Epäpuhtaalle iholle"), icon: "face", tileColor: "lilac", months: null, beauty: true,
    filter: () => facet("skinConcern", ["blemishes"]) },
  { slug: "concern-curly-hair", group: "beauty_concern", name: l("For curly hair", "Kiharille hiuksille"), icon: "waves", tileColor: "sunshineLight", months: null, beauty: true,
    filter: () => facet("hairType", ["curly", "coily"]) },
  // Fit collections (filters + Home collections, not separate trees)
  { slug: "fit-plus-size", group: "fit", name: l("Plus size", "Isot koot"), icon: "checkroom", tileColor: "lilac", months: null, filter: () => facet("fitCollection", ["plus_size"]) },
  { slug: "fit-maternity", group: "fit", name: l("Maternity", "Äitiys"), icon: "pregnant_woman", tileColor: "peach", months: null, filter: () => facet("fitCollection", ["maternity"]) },
  { slug: "fit-petite", group: "fit", name: l("Petite", "Petite"), icon: "checkroom", tileColor: "sand", months: null, filter: () => facet("fitCollection", ["petite"]) },
  { slug: "fit-tall", group: "fit", name: l("Tall", "Tall"), icon: "checkroom", tileColor: "clay", months: null, filter: () => facet("fitCollection", ["tall"]) },
  { slug: "fit-adaptive", group: "fit", name: l("Adaptive clothing", "Esteettömät vaatteet"), icon: "accessible", tileColor: "mint", months: null, filter: () => facet("fitCollection", ["adaptive"]) },
];
const DEFS = new Map(COLLECTION_DEFS.map((d) => [d.slug, d]));

export const MIN_ITEMS = (() => {
  const v = Number(process.env.CATALOG_COLLECTION_MIN_ITEMS);
  return Number.isInteger(v) && v >= 1 && v <= 100 ? v : 8;
})();

function helsinkiMonth(now = new Date()) {
  return Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Helsinki", month: "numeric" }).format(now));
}
export function inSeason(months: [number, number] | null, month = helsinkiMonth()) {
  if (!months) return true;
  const [from, to] = months;
  return from <= to ? month >= from && month <= to : month >= from || month <= to;
}

async function idsFn() {
  const idx = await categoryIndex();
  return (slugs: string[]) => slugs.map((s) => idx.bySlug.get(s)).filter((n) => n && n.active).map((n) => n!.id);
}

/** The products of a collection (for GET /products/search?collection=). null = unknown slug. */
export async function collectionFilter(slug: string): Promise<Prisma.ProductWhereInput | null> {
  const d = DEFS.get(slug);
  if (!d) return null;
  return d.filter(await idsFn());
}

async function beautyCategoryIds() {
  const idx = await categoryIndex();
  return idx.rows.filter((r) => r.parentId && BEAUTY_TOPS.includes(idx.byId.get(r.parentId)?.slug ?? "")).map((r) => r.id);
}

type Opts = { lat: number | null; lng: number | null; audience?: string; ageGroup?: string; month?: number };
const cache = new Map<string, { at: number; value: unknown }>();

/** GET /collections: the collections in season with at least MIN_ITEMS buyable products nearby. */
export async function activeCollections(o: Opts) {
  const key = JSON.stringify([o.lat === null ? null : Math.round(o.lat * 100), o.lng === null ? null : Math.round(o.lng * 100), o.audience ?? null, o.ageGroup ?? null, o.month ?? null]);
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < 30_000) return hit.value as Awaited<ReturnType<typeof build>>;
  const value = await build(o);
  if (cache.size > 500) cache.clear();
  cache.set(key, { at: Date.now(), value });
  return value;
}

export function invalidateCollections() {
  cache.clear();
}
registerCountCache(invalidateCollections);

async function build(o: Opts) {
  const ids = await idsFn();
  const storeIds = await storesInReach(o.lat, o.lng);
  const kids = isKidsView(o.audience, o.ageGroup);
  const base: Prisma.ProductWhereInput = { ...availableWhere(storeIds), ...audienceWhere(o.audience, o.ageGroup) };
  const noBeauty: Prisma.ProductWhereInput = kids ? { NOT: { categoryId: { in: await beautyCategoryIds() } } } : {};
  const month = o.month ?? helsinkiMonth();
  const candidates = COLLECTION_DEFS.filter((d) => inSeason(d.months, month) && !(kids && d.beauty));
  const counts = await Promise.all(candidates.map((d) => prisma.product.count({ where: { AND: [base, noBeauty, d.filter(ids)] } })));
  const collections = candidates.map((d, i) => ({
    slug: d.slug, group: d.group, name: d.name, icon: d.icon, tileColor: d.tileColor, count: counts[i],
    season: d.months ? { fromMonth: d.months[0], toMonth: d.months[1] } : null,
    // Where the app takes the shopper: search with the saved filter, or the brand index
    open: d.slug === "brands" ? { brands: "/api/v1/collections/brands" } : { search: `/api/v1/products/search?collection=${d.slug}` },
  })).filter((c) => c.count >= MIN_ITEMS);
  return { collections, minItems: MIN_ITEMS, month };
}

/** The A–Z brand index from product data (within reach). */
export async function brandIndex(o: Opts) {
  const storeIds = await storesInReach(o.lat, o.lng);
  const rows = await prisma.productFacet.groupBy({
    by: ["value"], where: { key: "brand", product: { ...availableWhere(storeIds), ...audienceWhere(o.audience, o.ageGroup) } }, _count: { _all: true },
  });
  const brands = rows
    .filter((r) => !["no brand", "merkitön", "merkiton"].includes(r.value))
    .map((r) => ({ value: r.value, name: r.value.replace(/(^|[\s-])(\p{L})/gu, (m) => m.toUpperCase()), count: r._count._all }))
    .sort((a, b) => a.value.localeCompare(b.value, "fi"))
    .slice(0, 1000)
    .map((b) => ({ ...b, letter: /^\p{L}/u.test(b.value) ? b.value[0].toUpperCase() : "#" }));
  return { brands };
}

const q = z.object({
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
  audience: z.enum(["WOMEN", "MEN", "KIDS", "UNISEX", "women", "men", "kids", "unisex", "all", "ALL"]).optional(),
  ageGroup: z.enum(["BABY", "TODDLER", "KIDS", "JUNIOR", "TEEN", "ADULT"]).optional(),
  month: z.coerce.number().int().min(1).max(12).optional(), // preview another month (admin / tests)
});

export const collectionRoutes = Router();
const pc = publicCache(30, 120);

function parse(req: Request): Opts | null {
  const r = q.safeParse(req.query);
  if (!r.success) return null;
  const a = r.data.audience?.toUpperCase();
  return { lat: r.data.lat ?? null, lng: r.data.lng ?? null, audience: a && a !== "ALL" ? a : undefined, ageGroup: r.data.ageGroup, month: r.data.month };
}

collectionRoutes.get("/collections", pc, async (req: Request, res: Response) => {
  const o = parse(req);
  if (!o) return res.status(400).json({ ok: false, error: "lat, lng, audience and month must be valid" });
  try {
    res.json({ ok: true, ...(await activeCollections(o)) });
  } catch (e) { sendError(res, e); }
});

collectionRoutes.get("/collections/brands", pc, async (req: Request, res: Response) => {
  const o = parse(req);
  if (!o) return res.status(400).json({ ok: false, error: "lat, lng and audience must be valid" });
  try {
    res.json({ ok: true, ...(await brandIndex(o)) });
  } catch (e) { sendError(res, e); }
});
