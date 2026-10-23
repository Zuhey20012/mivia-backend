import { Router, Request, Response } from "express";
import { z } from "zod";
import { sendError } from "../../lib/errors";
import { publicCache } from "../../middleware/httpCache";
import { backfillProducts, categoryDetail, categoryTree, ensureCategories } from "./categories";
import { ATTRS, attrsFor, facetKeysFor, facetLabel, FIBRES, valueLabel } from "./attributes";
import { SCHEMES } from "./certificates";
import { TEMPLATES, Template, isCosmetic } from "./taxonomy";
import { safetyRoutes } from "./safety";
import { recallApiRoutes } from "./recalls";
import { collectionRoutes } from "./collections";

/**
 * Public catalogue routes (mounted under /api/v1): the category tree with counts, one node with its facets, the
 * attribute templates for the store editor and the certificate schemes; plus the store-side safety routes, product
 * reports and recalls.
 */
export const catalogRoutes = Router();

const treeQuery = z.object({
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
  audience: z.enum(["WOMEN", "MEN", "KIDS", "UNISEX", "women", "men", "kids", "unisex", "all", "ALL"]).optional(),
  ageGroup: z.enum(["BABY", "TODDLER", "KIDS", "JUNIOR", "TEEN", "ADULT"]).optional(),
  includeEmpty: z.enum(["0", "1", "true", "false"]).optional(),
});

function parseTree(req: Request) {
  const q = treeQuery.safeParse(req.query);
  if (!q.success) return null;
  const a = q.data.audience?.toUpperCase();
  return {
    lat: q.data.lat ?? null, lng: q.data.lng ?? null,
    audience: a && a !== "ALL" ? a : undefined,
    ageGroup: q.data.ageGroup,
    includeEmpty: q.data.includeEmpty === "1" || q.data.includeEmpty === "true",
  };
}

// Counts change slowly: a short public cache (30 s in this process, plus Cache-Control for the apps / a CDN)
const cache = publicCache(30, 120);

catalogRoutes.get("/categories", cache, async (req: Request, res: Response) => {
  const o = parseTree(req);
  if (!o) return res.status(400).json({ ok: false, error: "lat, lng and audience must be valid" });
  try {
    res.json({ ok: true, ...(await categoryTree(o)) });
  } catch (e) { sendError(res, e); }
});

catalogRoutes.get("/categories/templates", cache, (_req: Request, res: Response) => {
  res.json({ ok: true, templates: TEMPLATES.map((t) => describeTemplate(t)) });
});

catalogRoutes.get("/categories/certificate-schemes", cache, (_req: Request, res: Response) => {
  res.json({ ok: true, schemes: Object.entries(SCHEMES).map(([key, s]) => ({ key, name: s.name, for: s.for })) });
});

catalogRoutes.get("/categories/:slug([a-z0-9-]+)", cache, async (req: Request, res: Response) => {
  const o = parseTree(req);
  if (!o) return res.status(400).json({ ok: false, error: "lat, lng and audience must be valid" });
  try {
    const d = await categoryDetail(req.params.slug, o);
    if (!d) return res.status(404).json({ ok: false, error: "Category not found" });
    res.json({ ok: true, ...d });
  } catch (e) { sendError(res, e); }
});

/** The editor's form for a template: fields with type, allowed values (with labels), level, plus option fields. */
export function describeTemplate(t: Template) {
  return {
    template: t,
    cosmetic: isCosmetic(t),
    fields: attrsFor(t).map((a) => ({
      key: a.key, label: a.label, type: a.kind, level: a.level ?? "optional",
      ...(a.values ? { values: a.values.map((v) => ({ value: v, label: valueLabel(String(v)) })) } : {}),
      ...(a.kind === "composition" ? { fibres: Object.entries(FIBRES).map(([value, label]) => ({ value, label })) } : {}),
      ...(a.max !== undefined ? { max: a.max } : {}), ...(a.min !== undefined ? { min: a.min } : {}), ...(a.maxItems ? { maxItems: a.maxItems } : {}),
    })),
    filters: facetKeysFor(t).map((k) => ({ key: k, label: facetLabel(k) })),
    optionFields: isCosmetic(t)
      ? ["shadeName", "shadeHex", "shadeFamily", "undertone", "finish", "contentAmount", "contentUnit"]
      : t === "HAIR_TOOL" || t === "BEAUTY_TOOL" ? ["color", "colourFamily"] : ["size", "color", "colourFamily", "measurements"],
  };
}

catalogRoutes.use(collectionRoutes);
catalogRoutes.use(safetyRoutes);
catalogRoutes.use(recallApiRoutes);

/** At start-up: create missing categories, then (once per database) map products made before 2.12.0. */
export async function initCatalog() {
  await ensureCategories();
  const mapped = await backfillProducts();
  return { mapped, attributes: ATTRS.length };
}
