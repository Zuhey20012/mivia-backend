import { ApiError } from "../../lib/errors";
import { fetchPublicJson } from "./safeFetch";
import {
  ImportIssue, ImportItem, ImportVariant, MAX_IMAGES_PER_PRODUCT, MAX_IMPORT_PRODUCTS, MAX_PRICE_CENTS, MAX_VARIANTS,
  cleanImageUrl, htmlToText, parseEuroCents, validGtin,
} from "./mapping";
import { COLOR_OPTION, SIZE_OPTION, USED_TAG } from "./shopify";
import { SHADE_OPTION, legacyCategory, mapTaxonomy, refineItem } from "./mapping";

/**
 * WooCommerce REST API (wc/v3) with the store's own read-only API keys. The keys are sent only as HTTP Basic
 * auth to the shop's own origin over https (never in a URL, never to a redirect target), live only in memory
 * for the duration of the job and are never stored or logged. Only GET requests are made.
 */
export type WooKeys = { consumerKey: string; consumerSecret: string };

type WooAttr = { id?: number; name?: string; option?: string; options?: string[]; variation?: boolean };
type WooVariation = {
  id?: number; price?: string; regular_price?: string; attributes?: WooAttr[]; manage_stock?: boolean | string;
  stock_quantity?: number | null; stock_status?: string; global_unique_id?: string; status?: string;
};
type WooProduct = {
  id?: number; name?: string; type?: string; status?: string; description?: string; short_description?: string;
  price?: string; regular_price?: string; manage_stock?: boolean; stock_quantity?: number | null; stock_status?: string;
  categories?: { name?: string }[]; tags?: { name?: string }[]; images?: { src?: string }[]; attributes?: WooAttr[];
  global_unique_id?: string;
};

const PER_PAGE = 100;
const MAX_PAGES = Math.ceil(MAX_IMPORT_PRODUCTS / PER_PAGE);

const api = (origin: URL, path: string) => new URL(`/wp-json/wc/v3${path}`, origin);
const basic = (k: WooKeys) => `Basic ${Buffer.from(`${k.consumerKey}:${k.consumerSecret}`).toString("base64")}`;

function errorFor(status: number) {
  if (status === 401 || status === 403) return "The shop refused the API keys. Create a Read key under WooCommerce → Settings → Advanced → REST API and paste it again.";
  if (status === 404) return "This site has no WooCommerce REST API at /wp-json/wc/v3 (is WooCommerce installed and are pretty permalinks on?)";
  return null;
}

function get(origin: URL, path: string, keys: WooKeys, maxBytes = 10 * 1024 * 1024) {
  return fetchPublicJson(api(origin, path), { maxBytes, timeoutMs: 20_000, authorization: basic(keys), errorFor });
}

/**
 * Woo prices are in the shop's currency (settings → general, or the current-currency endpoint). A shop that sells
 * in anything but euros is refused; when the currency cannot be read, the job carries a warning. Prices entered
 * without VAT also get a warning (Malvoya shows prices including VAT).
 */
export async function wooShopChecks(origin: URL, keys: WooKeys): Promise<ImportIssue[]> {
  const issues: ImportIssue[] = [];
  let currency = "";
  for (const path of ["/settings/general/woocommerce_currency", "/data/currencies/current"]) {
    try {
      const j = (await get(origin, path, keys, 256 * 1024)) as { value?: unknown; code?: unknown };
      const v = typeof j?.value === "string" ? j.value : typeof j?.code === "string" ? j.code : "";
      if (v) { currency = v.trim().toUpperCase().slice(0, 8); break; }
    } catch (e) {
      // Wrong keys are a hard stop; other failures just mean the currency stays unknown
      if (e instanceof ApiError && /refused the API keys|no WooCommerce REST API/.test(e.message)) throw e;
    }
  }
  if (!currency) issues.push({ item: "shop", message: "The shop's currency could not be confirmed; prices were read as euros. Check them before publishing.", level: "warning" });
  else if (currency !== "EUR") throw new ApiError(`This shop prices in ${currency}. Only shops that sell in euros can be imported.`, 400);
  try {
    const tax = (await get(origin, "/settings/tax/woocommerce_prices_include_tax", keys, 64 * 1024)) as { value?: unknown };
    if (tax?.value === "no") issues.push({ item: "shop", message: "The shop's prices are entered without VAT. Malvoya prices include VAT: check them before publishing.", level: "warning" });
  } catch { /* not readable with these keys: no warning */ }
  return issues;
}

/** Published products, 100 per page, up to MAX_IMPORT_PRODUCTS; stops at a short or empty page. */
export async function fetchWooProducts(origin: URL, keys: WooKeys): Promise<{ products: WooProduct[]; issues: ImportIssue[] }> {
  const all: WooProduct[] = [];
  const seen = new Set<number>();
  const issues: ImportIssue[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const json = await get(origin, `/products?status=publish&per_page=${PER_PAGE}&page=${page}&orderby=id&order=asc`, keys);
    if (!Array.isArray(json)) {
      if (page === 1) throw new ApiError("This is not a WooCommerce product list", 502);
      break;
    }
    const fresh = (json as WooProduct[]).filter((p) => typeof p?.id === "number" && !seen.has(p.id) && (seen.add(p.id), true));
    all.push(...fresh);
    if (json.length < PER_PAGE || !fresh.length) break;
    if (page === MAX_PAGES) issues.push({ item: "shop", message: `Only the first ${MAX_IMPORT_PRODUCTS} products are imported at a time`, level: "warning" });
  }
  return { products: all.slice(0, MAX_IMPORT_PRODUCTS), issues };
}

/** The variations of one variable product (first 100). */
export async function fetchWooVariations(origin: URL, keys: WooKeys, productId: number): Promise<WooVariation[]> {
  const json = await get(origin, `/products/${productId}/variations?per_page=${PER_PAGE}&orderby=id&order=asc`, keys);
  return Array.isArray(json) ? (json as WooVariation[]) : [];
}

const attrName = (a: WooAttr) => String(a.name ?? "").trim().replace(/^pa_/i, "");

function stockOf(v: { manage_stock?: boolean | string; stock_quantity?: number | null; stock_status?: string }, missing: { flag: boolean }) {
  if (v.manage_stock === true && typeof v.stock_quantity === "number" && Number.isFinite(v.stock_quantity)) {
    return Math.min(10000, Math.max(0, Math.floor(v.stock_quantity)));
  }
  if (v.stock_status === "outofstock") return 0;
  missing.flag = true;
  return 1;
}

/** Maps one WooCommerce product (simple or variable). Returns null (with an error) when it cannot be imported. */
export function mapWooProduct(p: WooProduct, variations: WooVariation[], issues: ImportIssue[]): ImportItem | null {
  const name = htmlToText(p.name ?? "", 200).trim();
  const label = name || `WooCommerce product ${p.id ?? "?"}`;
  const add = (message: string, level: ImportIssue["level"] = "warning") => issues.push({ item: label, message, level });
  if (typeof p.id !== "number") { add("Missing product id", "error"); return null; }
  if (name.length < 2) { add("Missing product name", "error"); return null; }
  if (p.type && p.type !== "simple" && p.type !== "variable") { add(`${p.type} products cannot be imported`, "error"); return null; }

  const missing = { flag: false };
  let base: number;
  let stockQuantity: number;
  const out: ImportVariant[] = [];
  let gtin = validGtin(p.global_unique_id);

  if (p.type === "variable") {
    const priced = variations
      .filter((v) => v.status === undefined || v.status === "publish")
      .map((v) => ({ v, cents: parseEuroCents(v.price || v.regular_price) }))
      .filter((x): x is { v: WooVariation; cents: number } => x.cents !== null);
    const usable = priced.filter((x) => x.cents <= MAX_PRICE_CENTS);
    if (usable.length < priced.length) add(`Options priced over ${MAX_PRICE_CENTS / 100} € were skipped`);
    if (!usable.length) { add(priced.length ? `Price over ${MAX_PRICE_CENTS / 100} €` : "No price", "error"); return null; }
    base = Math.min(...usable.map((x) => x.cents));
    const seen = new Set<string>();
    let otherOption = false;
    for (const { v, cents } of usable) {
      const attrs = v.attributes ?? [];
      let size = attrs.find((a) => SIZE_OPTION.test(attrName(a)))?.option?.trim().slice(0, 20) || undefined;
      const color = attrs.find((a) => COLOR_OPTION.test(attrName(a)))?.option?.trim().slice(0, 40) || undefined;
      const shadeName = attrs.find((a) => SHADE_OPTION.test(attrName(a)))?.option?.trim().slice(0, 40) || undefined;
      if (!size && !color && !shadeName) {
        // An attribute that is neither size nor colour (e.g. "Material"): kept as the size label
        size = attrs.map((a) => a.option).filter(Boolean).join(" / ").trim().slice(0, 20) || undefined;
        if (size) otherOption = true;
      }
      if (!size && !color && !shadeName) continue;
      const key = `${size ?? ""}|${color ?? ""}|${shadeName ?? ""}`.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      if (out.length >= MAX_VARIANTS) { add(`Only the first ${MAX_VARIANTS} options were imported`); break; }
      out.push({ size, color, ...(shadeName ? { shadeName } : {}), stock: stockOf(v, missing), priceAdjustCents: cents - base });
      gtin = gtin ?? validGtin(v.global_unique_id);
    }
    if (otherOption) add("An option that is not a size or colour was imported as the size; check it before publishing");
    if (!out.length) { add("No options with a size or colour", "error"); return null; }
    stockQuantity = out.reduce((s, v) => s + v.stock, 0);
  } else {
    const cents = parseEuroCents(p.price || p.regular_price);
    if (cents === null) { add("No price", "error"); return null; }
    if (cents > MAX_PRICE_CENTS) { add(`Price over ${MAX_PRICE_CENTS / 100} €`, "error"); return null; }
    base = cents;
    stockQuantity = stockOf(p, missing);
  }
  if (missing.flag) add("The shop does not track stock for this product: stock set to 1, check it before publishing");

  const images = (p.images ?? []).map((im) => (im.src ? cleanImageUrl(String(im.src)) : null)).filter((u): u is string => !!u);
  if ((p.images?.length ?? 0) > MAX_IMAGES_PER_PRODUCT) add(`Only the first ${MAX_IMAGES_PER_PRODUCT} photos were imported`);
  if (!images.length) add("No photos: add one before publishing");

  const tags = (p.tags ?? []).map((t) => String(t.name ?? "").trim().toLowerCase()).filter((t) => t && t.length <= 40).slice(0, 20);
  const categories = (p.categories ?? []).map((c) => htmlToText(c.name ?? "", 60)).filter(Boolean);
  const used = tags.some((t) => USED_TAG.test(t)) || categories.some((c) => USED_TAG.test(c.toLowerCase()));
  if (used) add("Tagged as used/vintage: condition set to Good, check it before publishing");

  const description = htmlToText(p.description || p.short_description) || undefined;
  // WooCommerce categories are often hierarchical ("Naiset", "Mekot"): the deepest one that names a subcategory wins
  const match = mapTaxonomy([...[...categories].reverse(), ...tags, name], description);
  const brandAttr = (p.attributes ?? []).find((a) => /^(brand|merkki|brändi|märke)$/i.test(attrName(a)));
  const brand = (p as any).brands?.[0]?.name ?? brandAttr?.options?.[0] ?? brandAttr?.option;
  return refineItem({
    externalId: String(p.id),
    label,
    name,
    description,
    category: legacyCategory(match),
    match,
    brand: typeof brand === "string" && brand.trim() ? brand.trim().slice(0, 60) : undefined,
    condition: used || match.secondHand ? "GOOD" : "NEW",
    isSecondHand: used || match.secondHand,
    tags,
    priceCents: base,
    stockQuantity,
    variants: out,
    imageUrls: images.slice(0, MAX_IMAGES_PER_PRODUCT),
    gtin,
  });
}
