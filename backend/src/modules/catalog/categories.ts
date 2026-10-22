import pino from "pino";
import { Prisma, Audience } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { haversineKm } from "../../utils/distance";
import { COLLECTIONS, SECOND_HAND_TOP, SUBS, TAXONOMY, Template } from "./taxonomy";
import { COLUMN_FILTERS, facetKeysFor, facetLabel, facetRows, valueLabel } from "./attributes";
import { matchTaxonomy } from "./matcher";
import { isGreenTag } from "./claims";
import { SCHEMES, liveCertificateWhere } from "./certificates";

const logger = pino({ name: "catalog" });

/**
 * Category tree service: the seeded Category rows (cached in memory for a minute; admin edits clear it), product counts
 * within delivery reach, facets with counts, and the product filters behind a category slug.
 */

export type CatRow = {
  id: number; slug: string; parentId: number | null; nameEn: string; nameFi: string; icon: string; tileColor: string;
  sort: number; template: string | null; isCollection: boolean; active: boolean;
};
type Index = { at: number; rows: CatRow[]; bySlug: Map<string, CatRow>; byId: Map<number, CatRow>; children: Map<number, CatRow[]> };

let index: Index | null = null;
const INDEX_TTL_MS = 60_000;

export async function categoryIndex(): Promise<Index> {
  if (index && Date.now() - index.at < INDEX_TTL_MS) return index;
  const rows = await prisma.category.findMany({ orderBy: [{ sort: "asc" }, { id: "asc" }] });
  const children = new Map<number, CatRow[]>();
  for (const r of rows) if (r.parentId) children.set(r.parentId, [...(children.get(r.parentId) ?? []), r]);
  index = { at: Date.now(), rows, bySlug: new Map(rows.map((r) => [r.slug, r])), byId: new Map(rows.map((r) => [r.id, r])), children };
  return index;
}

/** Called after an admin edit and after the seed. Also clears the counts cache. */
export function invalidateCategories() {
  index = null;
  treeCache.clear();
}

// ─── Seed and one-off backfill ───────────────────────────────────────────────

/**
 * Creates every node of catalog/taxonomy.ts that is missing. Existing nodes keep their names, order and visibility
 * (admins may have changed them); only the structure (parent, template, collection) follows the code.
 */
export async function ensureCategories() {
  const existing = new Map((await prisma.category.findMany()).map((c) => [c.slug, c]));
  const upsert = async (slug: string, data: { parentId: number | null; nameEn: string; nameFi: string; icon: string; tileColor: string; sort: number; template: string | null; isCollection: boolean }) => {
    const cur = existing.get(slug);
    if (!cur) {
      try {
        const created = await prisma.category.create({ data: { slug, ...data } });
        existing.set(slug, created);
        return created.id;
      } catch (e: any) {
        if (e?.code !== "P2002") throw e; // another instance created it at the same moment
        const again = await prisma.category.findUniqueOrThrow({ where: { slug } });
        existing.set(slug, again);
        return again.id;
      }
    }
    if (cur.parentId !== data.parentId || cur.template !== data.template || cur.isCollection !== data.isCollection) {
      await prisma.category.update({ where: { id: cur.id }, data: { parentId: data.parentId, template: data.template, isCollection: data.isCollection } });
    }
    return cur.id;
  };
  let created = 0;
  const before = existing.size;
  for (const [i, top] of TAXONOMY.entries()) {
    const topId = await upsert(top.slug, { parentId: null, nameEn: top.en, nameFi: top.fi, icon: top.icon, tileColor: top.tile, sort: (i + 1) * 10, template: null, isCollection: !!top.collections });
    for (const [j, c] of (top.children ?? []).entries()) {
      await upsert(c.slug, { parentId: topId, nameEn: c.en, nameFi: c.fi, icon: c.icon, tileColor: c.tile, sort: (j + 1) * 10, template: c.template, isCollection: false });
    }
    for (const [j, c] of (top.collections ?? []).entries()) {
      await upsert(c.slug, { parentId: topId, nameEn: c.en, nameFi: c.fi, icon: c.icon, tileColor: c.tile, sort: (j + 1) * 10, template: null, isCollection: true });
    }
  }
  created = existing.size - before;
  invalidateCategories();
  if (created) logger.info({ created }, "Categories seeded");
  return created;
}

/** Rewrites a product's facet rows from its attributes and options. */
export async function syncFacets(db: Prisma.TransactionClient | typeof prisma, productId: number) {
  const p = await db.product.findUnique({
    where: { id: productId },
    select: { attributes: true, categoryRef: { select: { template: true } }, variants: { select: { size: true, colourFamily: true, shadeFamily: true, undertone: true, finish: true } } },
  });
  if (!p) return;
  const rows = facetRows((p.categoryRef?.template as Template) ?? null, (p.attributes ?? {}) as Record<string, any>, p.variants);
  await db.productFacet.deleteMany({ where: { productId } });
  if (rows.length) await db.productFacet.createMany({ data: rows.map((r) => ({ productId, ...r })), skipDuplicates: true });
}

const BACKFILL_LEASE = "backfill:categories-v1";

/**
 * One-off (per database) mapping of products made before 2.12.0 onto the taxonomy with the import rules (spec §1.4,
 * input 4): the free-text category, then the name and tags, then the description. Matched products get the
 * subcategory, its English name as the legacy category, an audience when the words say so, and their facets. Home décor
 * and other out-of-scope goods are hidden and put on hold so the store picks a real category. Generic green tags go.
 * The JobLease row marks it done (and keeps two instances from running it at once).
 */
export async function backfillProducts() {
  try {
    await prisma.jobLease.create({ data: { name: BACKFILL_LEASE, lockedUntil: new Date(Date.now() + 3_600_000) } });
  } catch {
    return 0; // done before, or running on another instance
  }
  const idx = await categoryIndex();
  let lastId = 0;
  let mapped = 0;
  for (;;) {
    const batch = await prisma.product.findMany({
      where: { id: { gt: lastId } }, orderBy: { id: "asc" }, take: 200,
      select: { id: true, category: true, name: true, description: true, tags: true, categoryId: true, deletedAt: true, isSecondHand: true },
    });
    if (!batch.length) break;
    for (const p of batch) {
      lastId = p.id;
      const data: Prisma.ProductUncheckedUpdateInput = {};
      const tags = p.tags.filter((t) => !isGreenTag(t));
      if (tags.length !== p.tags.length) data.tags = tags;
      if (!p.categoryId && !p.deletedAt) {
        const m = matchTaxonomy([p.category, p.name, ...p.tags], p.description);
        const home = /^(home|koti|sisustus|koti ?& ?sisustus)$/i.test(p.category.trim());
        const node = m.slug ? idx.bySlug.get(m.slug) : undefined;
        if (node && !m.hold && !home) {
          data.categoryId = node.id;
          data.category = node.nameEn;
          mapped++;
        }
        if (m.audience) data.audience = m.audience;
        if (m.secondHand && !p.isSecondHand) data.isSecondHand = true;
        if (m.hold || home) { data.isAvailable = false; data.importHold = m.holdKey ?? "home_decor"; }
      }
      if (Object.keys(data).length) await prisma.product.update({ where: { id: p.id }, data });
      await syncFacets(prisma, p.id);
    }
  }
  await prisma.jobLease.update({ where: { name: BACKFILL_LEASE }, data: { lastRunAt: new Date() } });
  if (mapped) logger.info({ mapped }, "Existing products mapped onto the category taxonomy");
  return mapped;
}

// ─── Delivery reach and product filters ──────────────────────────────────────

/** How far a shop may be from the customer for its products to count in the tiles (km). */
export const REACH_KM = (() => {
  const v = Number(process.env.CATALOG_REACH_KM);
  return Number.isFinite(v) && v > 0 && v <= 200 ? v : 10;
})();

/** Verified stores within reach of a point (bounding box in SQL, then the exact distance). null = no location given. */
export async function storesInReach(lat: number | null, lng: number | null): Promise<number[] | null> {
  if (lat === null || lng === null || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const dLat = REACH_KM / 111;
  const dLng = REACH_KM / (111 * Math.max(0.05, Math.cos((lat * Math.PI) / 180)));
  const rows = await prisma.store.findMany({
    where: { isVerified: true, latitude: { gte: lat - dLat, lte: lat + dLat }, longitude: { gte: lng - dLng, lte: lng + dLng } },
    select: { id: true, latitude: true, longitude: true },
    take: 5000,
  });
  return rows.filter((s) => haversineKm(lat, lng, s.latitude!, s.longitude!) <= REACH_KM).map((s) => s.id);
}

/** Unisex products appear under both Women and Men. */
export function audienceWhere(audience: string | undefined | null): Prisma.ProductWhereInput {
  if (!audience) return {};
  const a = audience.toUpperCase();
  if (a === "WOMEN" || a === "MEN") return { audience: { in: [a as Audience, "UNISEX"] } };
  if (a === "KIDS" || a === "UNISEX") return { audience: a as Audience };
  return {};
}

/** What shoppers can buy: visible, in stock, not deleted, from an approved store (optionally within reach). */
export function availableWhere(storeIds: number[] | null): Prisma.ProductWhereInput {
  return {
    isAvailable: true, deletedAt: null, stockQuantity: { gt: 0 },
    store: { isVerified: true },
    ...(storeIds ? { storeId: { in: storeIds } } : {}),
  };
}

/** The products behind a category slug, descendants included; collections are their saved filters. null = unknown slug. */
export async function categoryFilter(slug: string): Promise<Prisma.ProductWhereInput | null> {
  const idx = await categoryIndex();
  const node = idx.bySlug.get(slug);
  if (!node || !node.active) return null;
  if (node.slug === SECOND_HAND_TOP) return { isSecondHand: true };
  if (node.isCollection) {
    const c = COLLECTIONS.get(node.slug);
    if (!c) return { isSecondHand: true };
    if (c.filter.top) {
      const top = idx.bySlug.get(c.filter.top);
      return { isSecondHand: true, categoryId: { in: (top ? idx.children.get(top.id) ?? [] : []).map((x) => x.id) } };
    }
    if (c.filter.facet) return { isSecondHand: true, facets: { some: { key: c.filter.facet[0], value: c.filter.facet[1] } } };
    if (c.filter.audience) return { isSecondHand: true, audience: c.filter.audience };
    return { isSecondHand: true };
  }
  if (node.parentId === null) return { categoryId: { in: (idx.children.get(node.id) ?? []).map((x) => x.id) } };
  return { categoryId: node.id };
}

/** The attribute templates behind a node (a top level has those of its children). */
export async function templatesOf(slug: string): Promise<Template[]> {
  const idx = await categoryIndex();
  const node = idx.bySlug.get(slug);
  if (!node) return [];
  if (node.template) return [node.template as Template];
  if (node.isCollection || node.slug === SECOND_HAND_TOP) {
    const c = COLLECTIONS.get(node.slug);
    const tops = c?.filter.top ? [c.filter.top] : ["clothing", "shoes", "bags", "accessories", "jewellery"];
    return [...new Set(tops.flatMap((t) => (TAXONOMY.find((x) => x.slug === t)?.children ?? []).map((ch) => ch.template)))];
  }
  return [...new Set((idx.children.get(node.id) ?? []).map((c) => c.template).filter(Boolean) as Template[])];
}

// ─── Tree with counts ────────────────────────────────────────────────────────

type TreeOpts = { lat: number | null; lng: number | null; audience?: string; includeEmpty?: boolean };
const treeCache = new Map<string, { at: number; value: unknown }>();
const TREE_TTL_MS = 30_000;

/** Product writes call this so counts never lag behind on this instance (other instances refresh within 30 s). */
export function invalidateCategoryCounts() {
  treeCache.clear();
}

function presentNode(n: CatRow, count: number) {
  return {
    slug: n.slug, name: { en: n.nameEn, fi: n.nameFi }, icon: n.icon, tileColor: n.tileColor,
    template: n.template, collection: n.isCollection, count,
  };
}

async function countsFor(base: Prisma.ProductWhereInput) {
  const [byCat, secondHand, designer, vintage, kids] = await Promise.all([
    prisma.product.groupBy({ by: ["categoryId"], where: base, _count: { _all: true } }),
    prisma.product.groupBy({ by: ["categoryId"], where: { ...base, isSecondHand: true }, _count: { _all: true } }),
    prisma.product.count({ where: { ...base, isSecondHand: true, facets: { some: { key: "brandTier", value: "designer" } } } }),
    prisma.product.count({ where: { ...base, isSecondHand: true, facets: { some: { key: "vintage", value: "true" } } } }),
    prisma.product.count({ where: { ...base, isSecondHand: true, audience: "KIDS" } }),
  ]);
  const toMap = (rows: { categoryId: number | null; _count: { _all: number } }[]) => new Map(rows.map((r) => [r.categoryId ?? 0, r._count._all]));
  return { byCat: toMap(byCat), sh: toMap(secondHand), designer, vintage, kids, shTotal: secondHand.reduce((s, r) => s + r._count._all, 0) };
}

function nodeCount(idx: Index, n: CatRow, c: Awaited<ReturnType<typeof countsFor>>): number {
  if (n.slug === SECOND_HAND_TOP) return c.shTotal;
  if (n.isCollection) {
    const col = COLLECTIONS.get(n.slug);
    if (col?.filter.top) {
      const top = idx.bySlug.get(col.filter.top);
      return (top ? idx.children.get(top.id) ?? [] : []).reduce((s, ch) => s + (c.sh.get(ch.id) ?? 0), 0);
    }
    if (col?.filter.facet?.[0] === "brandTier") return c.designer;
    if (col?.filter.facet?.[0] === "vintage") return c.vintage;
    if (col?.filter.audience) return c.kids;
    return 0;
  }
  if (n.parentId === null) return (idx.children.get(n.id) ?? []).reduce((s, ch) => s + (c.byCat.get(ch.id) ?? 0), 0);
  return c.byCat.get(n.id) ?? 0;
}

/** GET /categories: the tree with live counts of buyable products within reach; empty nodes hidden unless includeEmpty. */
export async function categoryTree(o: TreeOpts) {
  const key = JSON.stringify([o.lat === null ? null : Math.round(o.lat * 100), o.lng === null ? null : Math.round(o.lng * 100), o.audience ?? null, !!o.includeEmpty]);
  const hit = treeCache.get(key);
  if (hit && Date.now() - hit.at < TREE_TTL_MS) return hit.value as Awaited<ReturnType<typeof buildTree>>;
  const value = await buildTree(o);
  if (treeCache.size > 500) treeCache.clear();
  treeCache.set(key, { at: Date.now(), value });
  return value;
}

async function buildTree(o: TreeOpts) {
  const idx = await categoryIndex();
  const storeIds = await storesInReach(o.lat, o.lng);
  const counts = await countsFor({ ...availableWhere(storeIds), ...audienceWhere(o.audience) });
  const tops = idx.rows.filter((r) => r.parentId === null && r.active);
  const categories = tops.map((t) => {
    const children = (idx.children.get(t.id) ?? []).filter((c) => c.active)
      .map((c) => presentNode(c, nodeCount(idx, c, counts)))
      .filter((c) => o.includeEmpty || c.count > 0);
    return { ...presentNode(t, nodeCount(idx, t, counts)), children };
  }).filter((t) => o.includeEmpty || t.count > 0);
  return {
    categories,
    audience: o.audience ?? null,
    reach: { km: REACH_KM, located: storeIds !== null, stores: storeIds?.length ?? null },
  };
}

// ─── One node with breadcrumbs and facets ────────────────────────────────────

const MAX_FACET_VALUES = 30;

/** Facets (filters) available for a set of products, with counts. */
export async function facetsFor(templates: Template[], where: Prisma.ProductWhereInput) {
  const keys = [...new Set(templates.flatMap((t) => facetKeysFor(t)))];
  const [attrRows, conditions, audiences, certs] = await Promise.all([
    keys.length
      ? prisma.productFacet.groupBy({ by: ["key", "value"], where: { key: { in: keys }, product: where }, _count: { _all: true } })
      : Promise.resolve([] as { key: string; value: string; _count: { _all: number } }[]),
    prisma.product.groupBy({ by: ["condition"], where, _count: { _all: true } }),
    prisma.product.groupBy({ by: ["audience"], where, _count: { _all: true } }),
    prisma.productCertificate.findMany({
      where: { product: where, certificate: liveCertificateWhere() },
      select: { productId: true, certificate: { select: { scheme: true } } }, take: 5000,
    }),
  ]);
  const facets: { key: string; label: { en: string; fi: string }; values: { value: string; label: { en: string; fi: string }; count: number }[] }[] = [];
  for (const key of keys) {
    const values = attrRows.filter((r) => r.key === key)
      .map((r) => ({ value: r.value, label: key === "brand" ? { en: r.value, fi: r.value } : valueLabel(r.value), count: r._count._all }))
      .sort((a, b) => b.count - a.count).slice(0, MAX_FACET_VALUES);
    if (values.length) facets.push({ key, label: facetLabel(key), values });
  }
  const col = (key: string, rows: { value: string; count: number }[]) => {
    const values = rows.filter((r) => r.count > 0).map((r) => ({ ...r, label: valueLabel(r.value) })).sort((a, b) => b.count - a.count);
    if (values.length) facets.push({ key, label: COLUMN_FILTERS[key], values });
  };
  col("condition", conditions.map((r) => ({ value: r.condition, count: r._count._all })));
  col("audience", audiences.map((r) => ({ value: r.audience, count: r._count._all })));
  const byScheme = new Map<string, Set<number>>();
  for (const c of certs) byScheme.set(c.certificate.scheme, (byScheme.get(c.certificate.scheme) ?? new Set()).add(c.productId));
  const certValues = [...byScheme].map(([scheme, ids]) => ({ value: scheme, label: SCHEMES[scheme]?.name ?? { en: scheme, fi: scheme }, count: ids.size }))
    .sort((a, b) => b.count - a.count);
  if (certValues.length) facets.push({ key: "certificate", label: COLUMN_FILTERS.certificate, values: certValues });
  return facets;
}

/** GET /categories/:slug */
export async function categoryDetail(slug: string, o: TreeOpts) {
  const idx = await categoryIndex();
  const node = idx.bySlug.get(slug);
  if (!node || !node.active) return null;
  const parent = node.parentId ? idx.byId.get(node.parentId) ?? null : null;
  const storeIds = await storesInReach(o.lat, o.lng);
  const base = { ...availableWhere(storeIds), ...audienceWhere(o.audience) };
  const counts = await countsFor(base);
  const filter = (await categoryFilter(slug)) ?? {};
  const where = { AND: [base, filter] };
  const children = (idx.children.get(node.id) ?? []).filter((c) => c.active)
    .map((c) => presentNode(c, nodeCount(idx, c, counts)))
    .filter((c) => o.includeEmpty || c.count > 0);
  return {
    category: { ...presentNode(node, nodeCount(idx, node, counts)), parent: parent ? { slug: parent.slug, name: { en: parent.nameEn, fi: parent.nameFi } } : null },
    children,
    breadcrumbs: [...(parent ? [{ slug: parent.slug, name: { en: parent.nameEn, fi: parent.nameFi } }] : []), { slug: node.slug, name: { en: node.nameEn, fi: node.nameFi } }],
    facets: await facetsFor(await templatesOf(slug), where),
    reach: { km: REACH_KM, located: storeIds !== null },
  };
}

/** Search: categories matching a query, with their path (only visible nodes). */
export async function presentMatchedCategories(slugs: string[]) {
  const idx = await categoryIndex();
  return slugs.map((s) => idx.bySlug.get(s)).filter((n): n is CatRow => !!n && n.active).map((n) => {
    const parent = n.parentId ? idx.byId.get(n.parentId) : undefined;
    return {
      slug: n.slug, name: { en: n.nameEn, fi: n.nameFi }, icon: n.icon,
      path: [...(parent ? [{ slug: parent.slug, name: { en: parent.nameEn, fi: parent.nameFi } }] : []), { slug: n.slug, name: { en: n.nameEn, fi: n.nameFi } }],
    };
  });
}

export { SUBS };
