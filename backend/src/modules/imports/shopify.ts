import { fetchPublicJson } from "./safeFetch";
import {
  ImportIssue, ImportItem, ImportVariant, MAX_IMAGES_PER_PRODUCT, MAX_IMPORT_PRODUCTS, MAX_VARIANTS,
  cleanImageUrl, htmlToText, mapCategory, parseEuroCents, validGtin,
} from "./mapping";

/** The shop's public Shopify feed: /products.json?limit=250&page=N, at most 4 pages (1000 products). */

type ShopifyVariant = {
  id?: number | string; title?: string; price?: string | number; option1?: string | null; option2?: string | null; option3?: string | null;
  inventory_quantity?: number; available?: boolean; barcode?: string | null;
};
type ShopifyProduct = {
  id?: number | string; title?: string; body_html?: string | null; product_type?: string; tags?: string | string[];
  options?: { name?: string; position?: number }[]; variants?: ShopifyVariant[]; images?: { src?: string; position?: number }[];
};

const PAGE_SIZE = 250;
const MAX_PAGES = 4;
const SIZE_OPTION = /^(size|sizes|koko|storlek|größe|grösse|taille|talla|taglia)$/i;
const COLOR_OPTION = /^(colou?rs?|väri|värit|färg|farbe|couleur)$/i;
const USED_TAG = /^(used|vintage|second[- ]?hand|pre-?owned|preloved|käytetty|kierrätetty)$/i;

/**
 * Reads up to 4 pages. The public feed returns at most 250 products per request and some shops ignore
 * `page`, so reading stops at an empty page or a page with nothing new, and the job gets a warning when
 * the catalogue may have been cut off.
 */
export async function fetchShopifyProducts(origin: URL): Promise<{ products: ShopifyProduct[]; issues: ImportIssue[] }> {
  const all: ShopifyProduct[] = [];
  const seen = new Set<string>();
  const issues: ImportIssue[] = [];
  let lastPageFull = false;
  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = new URL(`/products.json?limit=${PAGE_SIZE}&page=${page}`, origin);
    const json = (await fetchPublicJson(url, { maxBytes: 10 * 1024 * 1024, timeoutMs: 20_000 })) as { products?: unknown };
    const products = Array.isArray(json?.products) ? (json.products as ShopifyProduct[]) : null;
    if (!products) {
      if (page === 1) throw new Error("NOT_A_SHOPIFY_FEED");
      break;
    }
    const fresh = products.filter((p) => {
      const id = String(p?.id ?? "");
      if (!id || seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    if (!fresh.length) {
      // The shop ignored `page` and sent the first page again: more products may exist than we can read
      if (products.length > 0 && lastPageFull) {
        issues.push({ item: "feed", message: `Only the first ${all.length} products could be read from the public feed`, level: "warning" });
      }
      lastPageFull = false;
      break;
    }
    all.push(...fresh);
    lastPageFull = products.length >= PAGE_SIZE;
    if (!lastPageFull || all.length >= MAX_IMPORT_PRODUCTS) break;
  }
  if (lastPageFull && all.length >= MAX_IMPORT_PRODUCTS) {
    issues.push({ item: "feed", message: `Only the first ${MAX_IMPORT_PRODUCTS} products are imported at a time`, level: "warning" });
  }
  return { products: all.slice(0, MAX_IMPORT_PRODUCTS), issues };
}

function tagsOf(p: ShopifyProduct): string[] {
  const raw = Array.isArray(p.tags) ? p.tags : typeof p.tags === "string" ? p.tags.split(",") : [];
  return raw.map((t) => String(t).trim().toLowerCase()).filter((t) => t && t.length <= 40).slice(0, 20);
}

/** Maps one Shopify product. Returns null (with an error) when it cannot be imported. */
export function mapShopifyProduct(p: ShopifyProduct, issues: ImportIssue[]): ImportItem | null {
  const name = String(p.title ?? "").trim().slice(0, 200);
  const label = name || `Shopify product ${p.id ?? "?"}`;
  const add = (message: string, level: ImportIssue["level"] = "warning") => issues.push({ item: label, message, level });
  if (p.id === undefined || p.id === null || String(p.id).length > 64) { add("Missing product id", "error"); return null; }
  if (name.length < 2) { add("Missing product name", "error"); return null; }

  const variants = (p.variants ?? []).filter((v) => parseEuroCents(v.price) !== null);
  if (!variants.length) { add("No price", "error"); return null; }

  // Which option holds the size and which the colour (Size / Koko, Colour / Väri)
  const options = (p.options ?? []).map((o, i) => ({ name: String(o.name ?? ""), index: (o.position ?? i + 1) - 1 }));
  const sizeIdx = options.find((o) => SIZE_OPTION.test(o.name.trim()))?.index;
  const colorIdx = options.find((o) => COLOR_OPTION.test(o.name.trim()))?.index;
  const valueAt = (v: ShopifyVariant, idx: number | undefined) => {
    if (idx === undefined) return undefined;
    const val = [v.option1, v.option2, v.option3][idx];
    return val && val !== "Default Title" ? String(val).trim() : undefined;
  };

  const prices = variants.map((v) => parseEuroCents(v.price)!);
  const base = Math.min(...prices);
  let missingStock = false;
  const stockOf = (v: ShopifyVariant) => {
    if (typeof v.inventory_quantity === "number" && Number.isFinite(v.inventory_quantity)) return Math.min(10000, Math.max(0, Math.floor(v.inventory_quantity)));
    if (v.available === false) return 0;
    missingStock = true;
    return 1;
  };

  const single = variants.length === 1 && (!variants[0].option1 || variants[0].option1 === "Default Title");
  const out: ImportVariant[] = [];
  let stockQuantity = 0;
  if (single) {
    stockQuantity = stockOf(variants[0]);
  } else {
    let otherOption = false;
    const seen = new Set<string>();
    for (const [i, v] of variants.entries()) {
      let size = valueAt(v, sizeIdx)?.slice(0, 20);
      const color = valueAt(v, colorIdx)?.slice(0, 40);
      if (!size && !color) {
        // An option that is neither size nor colour (e.g. "Material"): kept as the size label
        size = String(v.option1 ?? v.title ?? "").trim().slice(0, 20) || undefined;
        otherOption = true;
      }
      if (!size && !color) continue;
      const key = `${size ?? ""}|${color ?? ""}`.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      if (out.length >= MAX_VARIANTS) { add(`Only the first ${MAX_VARIANTS} options were imported`); break; }
      out.push({ size, color, stock: stockOf(v), priceAdjustCents: prices[i] - base });
    }
    if (otherOption) add("An option that is not a size or colour was imported as the size; check it before publishing");
    stockQuantity = out.reduce((s, v) => s + v.stock, 0);
  }
  if (missingStock) add("The shop does not publish stock levels: stock set to 1, check it before publishing");

  const images = [...(p.images ?? [])]
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    .map((im) => (im.src ? cleanImageUrl(String(im.src)) : null))
    .filter((u): u is string => !!u);
  if ((p.images?.length ?? 0) > MAX_IMAGES_PER_PRODUCT) add(`Only the first ${MAX_IMAGES_PER_PRODUCT} photos were imported`);
  if (!images.length) add("No photos: add one before publishing");

  const tags = tagsOf(p);
  const used = tags.some((t) => USED_TAG.test(t));
  if (used) add("Tagged as used/vintage: condition set to Good, check it before publishing");

  return {
    externalId: String(p.id),
    label,
    name,
    description: htmlToText(p.body_html) || undefined,
    category: mapCategory(p.product_type, ...tags, name),
    condition: used ? "GOOD" : "NEW",
    isSecondHand: used,
    tags,
    priceCents: base,
    stockQuantity,
    variants: out,
    imageUrls: images.slice(0, MAX_IMAGES_PER_PRODUCT),
    gtin: variants.map((v) => validGtin(v.barcode)).find(Boolean) ?? null,
  };
}
