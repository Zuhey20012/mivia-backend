/**
 * Shared mapping for catalogue imports (Shopify feed and CSV): categories, prices, text, the common item shape.
 */

import { TaxonomyMatch, matchTaxonomy } from "../catalog/matcher";
import { SUBS } from "../catalog/taxonomy";

/**
 * Category mapping (since 2.12.0): the taxonomy matcher of catalog/matcher.ts (spec §1.4: FI/EN keywords, Finnish
 * compounds by their last word, audience and second-hand words, out-of-scope goods held). Hints are given in priority
 * order; the description is the lowest-confidence hint.
 */
export function mapTaxonomy(hints: (string | null | undefined)[], description?: string | null): TaxonomyMatch {
  return matchTaxonomy(hints, description);
}

/** The legacy free-text category of a match: the subcategory's English name, or "Uncategorised". */
export function legacyCategory(m: TaxonomyMatch): string {
  return (m.slug && SUBS.get(m.slug)?.en) || "Uncategorised";
}

/** Option names that hold a shade (makeup, nails) rather than a size or colour. */
export const SHADE_OPTION = /^(shades?|sävy|sävyt|nyans|nyanser|teinte|farbton)$/i;
/** "30 ml", "50ml", "7,5 g": a beauty product's "Size" values are its content, not a clothing size (spec §1.4). */
const CONTENT_VALUE = /^(\d{1,5}(?:[.,]\d{1,2})?)\s*(ml|g)$/i;

export function parseContent(v: string | null | undefined): { amount: number; unit: "ml" | "g" } | null {
  const m = (v ?? "").trim().match(CONTENT_VALUE);
  return m ? { amount: Number(m[1].replace(",", ".")), unit: m[2].toLowerCase() as "ml" | "g" } : null;
}

/** Sizes that are really contents become contentAmount/contentUnit; a title like "Serum 30 ml" gives the product content. */
export function refineItem(item: ImportItem): ImportItem {
  const variants = item.variants.map((v) => {
    const c = parseContent(v.size);
    return c ? { ...v, size: undefined, contentAmount: c.amount, contentUnit: c.unit } : v;
  }).filter((v) => v.size || v.color || v.shadeName || v.contentAmount);
  let content = item.content ?? null;
  if (!content && !variants.some((v) => v.contentAmount)) {
    const m = item.name.match(/(\d{1,5}(?:[.,]\d{1,2})?)\s*(ml|g)\b/i);
    if (m) content = { amount: Number(m[1].replace(",", ".")), unit: m[2].toLowerCase() as "ml" | "g" };
  }
  return { ...item, variants, content };
}

/** "12,90" / "12.90" / "12" / "12,90 €" → 1290 cents; null when it is not a plain euro amount. */
/** Highest price an import accepts (100 000 €). */
export const MAX_PRICE_CENTS = 10_000_000;

export function parseEuroCents(raw: unknown): number | null {
  if (typeof raw === "number") return Number.isFinite(raw) && raw > 0 ? Math.round(raw * 100) : null;
  if (typeof raw !== "string") return null;
  const v = raw.replace(/€|eur/gi, "").replace(/\s/g, "");
  const m = v.match(/^(\d{1,6})(?:[.,](\d{1,2}))?$/);
  if (!m) return null;
  const cents = Number(m[1]) * 100 + Number((m[2] ?? "0").padEnd(2, "0"));
  return cents > 0 ? cents : null;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

/** HTML → plain text (paragraphs kept as new lines), at most `max` characters. */
export function htmlToText(html: string | null | undefined, max = 2000): string {
  if (!html) return "";
  const text = html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, "\n")
    .replace(/<li[^>]*>/gi, "• ")
    .replace(/<[^>]*>/g, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Math.min(Number(n), 0x10ffff)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(Math.min(parseInt(n, 16), 0x10ffff)))
    .replace(/&([a-z]+);/gi, (m, n) => ENTITIES[n.toLowerCase()] ?? m)
    .replace(/[ \t\f\v ]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

/** EAN/GTIN: 8–14 digits. */
export function validGtin(v: string | null | undefined): string | null {
  const s = (v ?? "").replace(/\s/g, "");
  return /^\d{8,14}$/.test(s) ? s : null;
}

/** Only https photo addresses are passed to Cloudinary ("//cdn…" is read as https). */
export function cleanImageUrl(raw: string): string | null {
  let s = raw.trim();
  if (s.startsWith("//")) s = `https:${s}`;
  try {
    const u = new URL(s);
    return u.protocol === "https:" && !u.username && !u.password && s.length <= 2000 ? u.toString() : null;
  } catch {
    return null;
  }
}

export type ImportVariant = {
  size?: string; color?: string; stock: number; priceAdjustCents: number;
  shadeName?: string; shadeHex?: string; contentAmount?: number; contentUnit?: "ml" | "g";
};

/** One product as read from a source, before photos are copied and it is saved. */
export type ImportItem = {
  externalId: string;
  label: string; // shown in the job's error list
  name: string;
  description?: string;
  /** Legacy free text: the subcategory's English name (or "Uncategorised") */
  category: string;
  /** The taxonomy match: categoryId, audience, second-hand, out-of-scope hold (2.12) */
  match: TaxonomyMatch;
  brand?: string;
  /** Content of the pack when the product has no options with their own */
  content?: { amount: number; unit: "ml" | "g" } | null;
  condition: "NEW" | "LIKE_NEW" | "GOOD" | "FAIR" | "POOR";
  isSecondHand?: boolean;
  tags: string[];
  priceCents: number; // VAT-inclusive EUR, the lowest option price
  stockQuantity: number;
  variants: ImportVariant[];
  imageUrls: string[];
  gtin?: string | null;
};

export type ImportIssue = { item: string; message: string; level: "error" | "warning" };

export const MAX_IMPORT_PRODUCTS = 1000;
export const MAX_IMAGES_PER_PRODUCT = 5;
export const MAX_VARIANTS = 60;
