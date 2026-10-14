/**
 * Shared mapping for catalogue imports (Shopify feed and CSV): categories, prices, text, the common item shape.
 */

/** The categories the store app offers (malvoya_vendor product editor). Imports map onto these. */
export const PRODUCT_CATEGORIES = ["Clothing", "Shoes", "Bags", "Accessories", "Jewelry", "Beauty", "Home", "Other"] as const;

// Order matters: the more specific categories are checked before the broad "Clothing" words.
const KEYWORDS: [string, RegExp][] = [
  ["Shoes", /\b(shoes?|sneakers?|boots?|sandals?|heels|loafers?|slippers?|kenk|tennari|saapa|sandaal|tossu)/i],
  ["Bags", /\b(bags?|backpacks?|handbags?|totes?|purses?|wallets?|laukku|laukut|reppu|lompakko|kassi)/i],
  ["Jewelry", /\b(jewel|necklaces?|rings?|earrings?|bracelets?|pendants?|koru|sormus|riipus)/i],
  ["Beauty", /\b(beauty|cosmetics?|make-?up|lipsticks?|skin ?care|creams?|perfumes?|serum|kosmetiik|meikki|huulipuna|ihonhoito|voide|hajuvesi)/i],
  ["Home", /\b(home|decor|candles?|pillows?|cushions?|blankets?|towels?|vases?|sisustus|kynttil|tyyny|peitto|pyyhe|maljakko)/i],
  ["Accessories", /\b(accessor|hats?|caps?|scarf|scarves|belts?|gloves?|mittens?|sunglasses|ties?|beanies?|asuste|hattu|pipo|huivi|vyö|käsine|lapanen|aurinkolasi)/i],
  ["Clothing", /\b(cloth|apparel|dress|shirt|t-shirt|tees?|tops?|blouse|jacket|coat|jeans|trousers|pants|skirt|sweater|hoodie|knit|shorts|suit|vaate|mekko|paita|takki|housut|farkut|hame|neule|huppari|shortsit|pusero)/i],
];

/** First hint that names a valid category (any case) wins; then keywords (en/fi); otherwise "Other". */
export function mapCategory(...hints: (string | null | undefined)[]): string {
  const clean = hints.map((h) => (h ?? "").trim()).filter(Boolean);
  for (const h of clean) {
    const exact = PRODUCT_CATEGORIES.find((c) => c.toLowerCase() === h.toLowerCase());
    if (exact) return exact;
  }
  for (const h of clean) {
    for (const [cat, re] of KEYWORDS) if (re.test(h)) return cat;
  }
  return "Other";
}

/** "12,90" / "12.90" / "12" / "12,90 €" → 1290 cents; null when it is not a plain euro amount. */
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

export type ImportVariant = { size?: string; color?: string; stock: number; priceAdjustCents: number };

/** One product as read from a source, before photos are copied and it is saved. */
export type ImportItem = {
  externalId: string;
  label: string; // shown in the job's error list
  name: string;
  description?: string;
  category: string;
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
