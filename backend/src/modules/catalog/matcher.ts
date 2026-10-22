import {
  AUDIENCE_WORDS, CHILD_GENDER_WORDS, HOLD_WORDS, SECOND_HAND_WORDS, SUBS, TAXONOMY, TOPS,
} from "./taxonomy";

/**
 * One shared mapper from free text to the taxonomy (spec §1.4), used by the Shopify, WooCommerce and CSV imports, the
 * one-off backfill of old products and the search ("huulipuna" → Makeup › Lips).
 *
 * Matching rules: lowercase; accents are stripped only for comparison (kengat = kengät); English keywords match as
 * whole words (a plural s/es optional either way); Finnish keywords of 4+ letters also match as the END of a word,
 * because Finnish compounds put the head noun last (iltamekko → mekko, talvitakki → takki). Phrases match at word
 * boundaries. The longest keyword wins; on a tie a subcategory beats a top level. Hints are tried in priority order and
 * the first one that names a subcategory wins.
 */

export function fold(s: string): string {
  return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").normalize("NFC");
}

/** Lowercase, accents stripped, punctuation (except inner hyphens) → spaces, single spaces, padded with spaces. */
export function normalizeText(s: string): string {
  const t = fold(s)
    .replace(/[^\p{L}\p{N}\- ]+/gu, " ")
    .replace(/(^|\s)-+|-+(\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return ` ${t} `;
}

type Kw = { word: string; lang: "fi" | "en"; slug: string; level: "sub" | "top" };

function buildKeywords(): Kw[] {
  const out: Kw[] = [];
  for (const top of TAXONOMY) {
    for (const w of top.kwFi ?? []) out.push({ word: fold(w), lang: "fi", slug: top.slug, level: "top" });
    for (const w of top.kwEn ?? []) out.push({ word: fold(w), lang: "en", slug: top.slug, level: "top" });
    for (const c of top.children ?? []) {
      // The display names count too (exact path and name matches are handled separately, this helps free text)
      for (const w of c.kwFi ?? []) out.push({ word: fold(w), lang: "fi", slug: c.slug, level: "sub" });
      for (const w of c.kwEn ?? []) out.push({ word: fold(w), lang: "en", slug: c.slug, level: "sub" });
    }
  }
  return out;
}
const KEYWORDS = buildKeywords();

/** Does the normalized text (padded with spaces) contain the keyword under the rules above? */
function hits(text: string, kw: string, lang: "fi" | "en"): boolean {
  if (kw.includes(" ")) return text.includes(` ${kw} `);
  const words = text.trim().split(" ");
  for (const w of words) {
    if (w === kw) return true;
    if (lang === "en" || kw.length < 4) {
      // plural either way: dress ↔ dresses, earring ↔ earrings
      if (w === `${kw}s` || w === `${kw}es` || (kw.endsWith("s") && w === kw.slice(0, -1))) return true;
      // hyphenated forms: "t-shirt" in "t-shirts" handled above; a compound with a hyphen ("weekend-laukku")
      if (w.includes("-") && w.split("-").includes(kw)) return true;
    } else if (w.endsWith(kw)) {
      return true;
    } else if (w.includes("-") && w.split("-").some((part) => part === kw || part.endsWith(kw))) {
      return true;
    }
  }
  return false;
}

export type TaxonomyMatch = {
  /** A subcategory slug, or null when nothing confident matched */
  slug: string | null;
  /** Only a top level matched (the store must pick the subcategory) */
  topOnly: string | null;
  audience: "WOMEN" | "MEN" | "KIDS" | "UNISEX" | null;
  secondHand: boolean;
  vintage: boolean;
  /** Out-of-scope goods: the reason the draft is held (holdKey is stored on the product) */
  hold: { en: string; fi: string } | null;
  holdKey: string | null;
  /** The keyword or name that decided it (for the import report) */
  matched: string | null;
};

/** Exact slug, "Clothing > Dresses" / "Vaatteet > Mekot" paths, or an exact FI/EN subcategory name. */
export function exactCategory(raw: string | null | undefined): string | null {
  const v = (raw ?? "").trim();
  if (!v) return null;
  if (SUBS.has(v.toLowerCase())) return v.toLowerCase();
  const parts = v.split(/\s*(?:>|›|\/|»)\s*/).filter(Boolean);
  const last = fold(parts[parts.length - 1] ?? "");
  const top = parts.length > 1 ? fold(parts[0]) : null;
  for (const [slug, s] of SUBS) {
    if (fold(s.en) !== last && fold(s.fi) !== last) continue;
    if (top) {
      const t = TOPS.get(s.top)!;
      if (fold(t.en) !== top && fold(t.fi) !== top) continue;
    }
    return slug;
  }
  return null;
}

function bestKeyword(text: string): { slug: string; level: "sub" | "top"; word: string } | null {
  const norm = normalizeText(text);
  let best: (Kw & { len: number }) | null = null;
  for (const k of KEYWORDS) {
    if (!hits(norm, k.word, k.lang)) continue;
    const len = k.word.length;
    if (!best || len > best.len || (len === best.len && k.level === "sub" && best.level === "top")) best = { ...k, len };
  }
  return best ? { slug: best.slug, level: best.level, word: best.word } : null;
}

function wordsIn(text: string, words: string[]): string | null {
  const norm = normalizeText(text);
  for (const w of words) {
    const f = fold(w);
    if (f.includes(" ") ? norm.includes(` ${f} `) : norm.includes(` ${f} `) || norm.trim().split(" ").some((x) => x.length > f.length + 2 && f.length >= 6 && x.endsWith(f))) return w;
  }
  return null;
}

/**
 * Maps free-text hints (highest priority first) onto the taxonomy. `description` is the lowest-confidence hint: used for
 * the category only when nothing else matched, and never for audience, second-hand or hold words.
 */
export function matchTaxonomy(hints: (string | null | undefined)[], description?: string | null): TaxonomyMatch {
  const clean = hints.map((h) => (h ?? "").trim()).filter(Boolean);
  const all = clean.join(" \n ");
  const res: TaxonomyMatch = { slug: null, topOnly: null, audience: null, secondHand: false, vintage: false, hold: null, holdKey: null, matched: null };

  for (const h of HOLD_WORDS) {
    const w = wordsIn(all, h.words);
    if (w) { res.hold = h.reason; res.holdKey = h.key; res.matched = w; break; }
  }
  // Audience: several different ones (women + men) → unisex; girls/boys are kids
  const found = new Set<string>();
  const norm = normalizeText(all);
  const tokens = norm.trim().split(" ");
  for (const a of AUDIENCE_WORDS) {
    const hit = a.words.some((w) => norm.includes(` ${fold(w)} `))
      || (a.prefixes ?? []).some((p) => tokens.some((t) => t.length > p.length + 3 && t.startsWith(fold(p))));
    if (hit) found.add(a.audience);
  }
  if (CHILD_GENDER_WORDS.some((w) => norm.includes(` ${fold(w)} `))) { found.delete("WOMEN"); found.delete("MEN"); found.add("KIDS"); }
  if (found.has("KIDS")) res.audience = "KIDS";
  else if (found.has("UNISEX") || (found.has("WOMEN") && found.has("MEN"))) res.audience = "UNISEX";
  else if (found.size === 1) res.audience = [...found][0] as TaxonomyMatch["audience"];

  if (wordsIn(all, SECOND_HAND_WORDS)) res.secondHand = true;
  if (norm.includes(" vintage ")) res.vintage = true;

  for (const h of clean) {
    const exact = exactCategory(h);
    if (exact) { res.slug = exact; res.matched = h; return res; }
  }
  let top: string | null = null;
  for (const h of clean) {
    const k = bestKeyword(h);
    if (k?.level === "sub") { res.slug = k.slug; res.matched = k.word; return res; }
    if (k && !top) top = k.slug;
  }
  if (description) {
    const k = bestKeyword(description);
    if (k?.level === "sub" && !top) { res.slug = k.slug; res.matched = k.word; return res; }
    if (k && !top) top = k.slug;
  }
  if (top) {
    // Only a top level: clothing has an "other" child; elsewhere the store picks (never guessed)
    if (top === "clothing") res.slug = "clothing-other";
    else res.topOnly = top;
  }
  return res;
}

/** Categories that match a search phrase: keywords (huulipuna → makeup-lips) and names in either language. */
export function categoriesForQuery(q: string, limit = 5): string[] {
  const out: string[] = [];
  const add = (s: string) => { if (!out.includes(s) && out.length < limit) out.push(s); };
  const k = bestKeyword(q);
  if (k) add(k.slug);
  const f = fold(q.trim());
  if (f.length >= 3) {
    for (const [slug, s] of SUBS) if (fold(s.en).includes(f) || fold(s.fi).includes(f)) add(slug);
    for (const [slug, t] of TOPS) if (fold(t.en).includes(f) || fold(t.fi).includes(f)) add(slug);
  }
  return out;
}
