/**
 * Unit price (Price Indication Directive 98/6/EC; Finnish decree 553/2013 §3, §4, §10): goods sold by volume or weight
 * show the price per litre or per kilogram, in Finland never per 100 ml / 100 g. Not needed for pre-packages of less
 * than 50 ml or 50 g, or for items sold by the piece. Always computed from the price actually charged (so a reduced
 * price gets a reduced unit price), never typed by the shop.
 */
export type UnitPrice = { cents: number; per: "l" | "kg" } | null;

export const UNIT_PRICE_MIN_CONTENT = 50;

export function unitPriceFor(priceCents: number | null | undefined, amount: number | null | undefined, unit: string | null | undefined): UnitPrice {
  if (priceCents === null || priceCents === undefined || !amount || !(amount > 0)) return null;
  if (unit !== "ml" && unit !== "g") return null;
  if (amount < UNIT_PRICE_MIN_CONTENT) return null; // §10(2): pre-packages under 50 ml / 50 g
  return { cents: Math.round((priceCents * 1000) / amount), per: unit === "ml" ? "l" : "kg" };
}

/** "1 780,00 €/l" (fi) or "1,780.00 €/l" (en). */
export function unitPriceText(u: UnitPrice, locale: "fi" | "en"): string | null {
  if (!u) return null;
  const n = (u.cents / 100).toFixed(2);
  const [int, dec] = n.split(".");
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, locale === "fi" ? " " : ",");
  return `${grouped}${locale === "fi" ? "," : "."}${dec} €/${u.per}`;
}
