import { ApiError } from "../../lib/errors";
import {
  ImportIssue, ImportItem, MAX_IMAGES_PER_PRODUCT, MAX_IMPORT_PRODUCTS, MAX_VARIANTS,
  MAX_PRICE_CENTS, cleanImageUrl, legacyCategory, mapTaxonomy, parseEuroCents, refineItem, validGtin,
} from "./mapping";

/**
 * CSV catalogue: UTF-8, header row, comma or semicolon separated, quotes as in RFC 4180.
 * Columns: name, description, category, price, size, colour, stock, image_urls (| separated), condition,
 * gtin, external_id. Rows with the same external_id (or the same name when it is empty) are one product,
 * each row one size/colour option.
 */

export const CSV_COLUMNS = [
  "name", "description", "category", "price", "size", "colour", "stock", "image_urls", "condition", "gtin", "external_id",
  // 2.12: a category slug (preferred over "category"), audience, brand, shade per row, content per row
  "category_slug", "audience", "brand", "shade", "shade_hex", "content_ml", "content_g",
] as const;
const ALIASES: Record<string, string> = {
  color: "colour", väri: "colour", koko: "size", nimi: "name", hinta: "price", images: "image_urls", image_url: "image_urls", ean: "gtin", id: "external_id", sku: "external_id",
  kategoria: "category", merkki: "brand", sävy: "shade", kenelle: "audience",
};
const AUDIENCES = new Map<string, "WOMEN" | "MEN" | "KIDS" | "UNISEX">([
  ["women", "WOMEN"], ["naiset", "WOMEN"], ["men", "MEN"], ["miehet", "MEN"], ["kids", "KIDS"], ["lapset", "KIDS"], ["unisex", "UNISEX"],
]);
const MAX_ROWS = 5000;
const CONDITIONS = new Map<string, ImportItem["condition"]>([
  ["new", "NEW"], ["uusi", "NEW"], ["like_new", "LIKE_NEW"], ["like new", "LIKE_NEW"], ["kuin uusi", "LIKE_NEW"],
  ["good", "GOOD"], ["hyvä", "GOOD"], ["fair", "FAIR"], ["kohtalainen", "FAIR"], ["poor", "POOR"], ["huono", "POOR"],
]);

/** Splits CSV text into rows of fields. The delimiter is whichever of ; and , appears more in the header. */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, "");
  const firstLine = src.split(/\r?\n/, 1)[0] ?? "";
  const delim = (firstLine.match(/;/g)?.length ?? 0) > (firstLine.match(/,/g)?.length ?? 0) ? ";" : ",";
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += ch;
    } else if (ch === '"' && field === "") quoted = true;
    else if (ch === delim) { row.push(field); field = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && src[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = "";
    } else field += ch;
  }
  if (field !== "" || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((f) => f.trim() !== ""));
}

/** Reads and validates the whole CSV. Header problems throw (400); row problems are collected. */
export function csvToItems(text: string): { items: ImportItem[]; issues: ImportIssue[]; skipped: number; groups: number } {
  const rows = parseCsv(text);
  if (rows.length < 2) throw new ApiError("The CSV needs a header row and at least one product row", 400);
  const header = rows[0].map((h) => {
    const k = h.trim().toLowerCase().replace(/\s+/g, "_");
    return ALIASES[k] ?? k;
  });
  for (const required of ["name", "price"]) {
    if (!header.includes(required)) throw new ApiError(`The CSV header must have a "${required}" column`, 400);
  }
  if (rows.length - 1 > MAX_ROWS) throw new ApiError(`At most ${MAX_ROWS} rows per file`, 400);

  const issues: ImportIssue[] = [];
  const unknown = header.filter((h) => h && !(CSV_COLUMNS as readonly string[]).includes(h));
  if (unknown.length) issues.push({ item: "header", message: `Ignored columns: ${unknown.join(", ").slice(0, 200)}`, level: "warning" });

  type Row = { line: number; get: (c: string) => string };
  const groups = new Map<string, {
    key: string; rows: { row: Row; priceCents: number; stock: number; size?: string; color?: string }[]; bad: number; options: Set<string>;
  }>();

  for (let r = 1; r < rows.length; r++) {
    const line = r + 1; // the header is row 1
    const cells = rows[r];
    const row: Row = { line, get: (c) => (cells[header.indexOf(c)] ?? "").trim() };
    const fail = (message: string) => issues.push({ item: `row ${line}`, message, level: "error" });
    const name = row.get("name");
    const externalId = row.get("external_id");
    const key = externalId ? `id:${externalId.slice(0, 64)}` : `name:${name.toLowerCase()}`;
    const group = groups.get(key) ?? { key, rows: [], bad: 0, options: new Set<string>() };
    groups.set(key, group);

    // More cells than columns: usually an unquoted decimal comma ("12,90") in a comma-separated file
    if (cells.length > header.length && cells.slice(header.length).some((c) => c.trim() !== "")) {
      fail(`this row has more cells (${cells.length}) than the header (${header.length}). Put prices like 12,90 in quotes, or separate the columns with semicolons`);
      group.bad++;
      continue;
    }

    const problems: string[] = [];
    if (name.length < 2 || name.length > 200) problems.push("name must be 2–200 characters");
    const priceCents = parseEuroCents(row.get("price"));
    if (priceCents === null || priceCents > MAX_PRICE_CENTS) problems.push(`price "${row.get("price").slice(0, 20)}" is not a euro amount like 12,90`);
    const stockRaw = row.get("stock");
    const stock = stockRaw === "" ? 1 : /^\d{1,5}$/.test(stockRaw) && Number(stockRaw) <= 10000 ? Number(stockRaw) : NaN;
    if (Number.isNaN(stock)) problems.push("stock must be a whole number 0–10000");
    const condition = row.get("condition");
    if (condition && !CONDITIONS.has(condition.toLowerCase().replace(/-/g, " ").replace(/_/g, " ")) && !CONDITIONS.has(condition.toLowerCase())) {
      problems.push("condition must be NEW, LIKE_NEW, GOOD, FAIR or POOR");
    }
    const gtin = row.get("gtin");
    if (gtin && !validGtin(gtin)) problems.push("gtin must be 8–14 digits");
    if (row.get("size").length > 20) problems.push("size is longer than 20 characters");
    if (row.get("colour").length > 40) problems.push("colour is longer than 40 characters");
    if (row.get("description").length > 2000) problems.push("description is longer than 2000 characters");
    if (row.get("shade").length > 40) problems.push("shade is longer than 40 characters");
    if (row.get("shade_hex") && !/^#[0-9A-Fa-f]{6}$/.test(row.get("shade_hex"))) problems.push("shade_hex must look like #A0522D");
    for (const c of ["content_ml", "content_g"]) if (row.get(c) && !/^\d{1,5}(?:[.,]\d{1,2})?$/.test(row.get(c))) problems.push(`${c} must be a number`);
    if (row.get("audience") && !AUDIENCES.has(row.get("audience").toLowerCase())) problems.push("audience must be women, men, kids or unisex");
    if (problems.length) { fail(problems.join("; ")); group.bad++; continue; }

    const size = row.get("size") || undefined;
    const color = row.get("colour") || row.get("shade") || undefined;
    const optionKey = `${(size ?? "").toLowerCase()}|${(color ?? "").toLowerCase()}|${row.get("content_ml")}|${row.get("content_g")}`;
    if (group.options.has(optionKey)) {
      fail(size || color ? "the same size/colour appears twice for this product" : "duplicate product row (give each row a size or colour, or a different external_id)");
      group.bad++;
      continue;
    }
    group.options.add(optionKey);
    group.rows.push({ row, priceCents: priceCents!, stock, size, color: row.get("colour") || undefined });
  }

  const items: ImportItem[] = [];
  let skipped = 0;
  for (const g of groups.values()) {
    if (!g.rows.length) { skipped++; continue; }
    if (items.length >= MAX_IMPORT_PRODUCTS) {
      skipped++;
      issues.push({ item: `row ${g.rows[0].row.line}`, message: `Only ${MAX_IMPORT_PRODUCTS} products per import`, level: "error" });
      continue;
    }
    const first = g.rows[0].row;
    const label = first.get("name").slice(0, 200);
    const optionOf = (x: (typeof g.rows)[number]) => {
      const ml = x.row.get("content_ml"), gr = x.row.get("content_g");
      return {
        size: x.size, color: x.color, stock: x.stock, priceAdjustCents: 0,
        ...(x.row.get("shade") ? { shadeName: x.row.get("shade"), ...(x.row.get("shade_hex") ? { shadeHex: x.row.get("shade_hex") } : {}) } : {}),
        ...(ml ? { contentAmount: Number(ml.replace(",", ".")), contentUnit: "ml" as const } : gr ? { contentAmount: Number(gr.replace(",", ".")), contentUnit: "g" as const } : {}),
      };
    };
    const isOption = (x: (typeof g.rows)[number]) => !!(x.size || x.color || x.row.get("shade") || (g.rows.length > 1 && (x.row.get("content_ml") || x.row.get("content_g"))));
    const withOptions = g.rows.filter(isOption);
    if (g.rows.length > 1 && withOptions.length !== g.rows.length) {
      skipped++;
      issues.push({ item: `row ${first.line}`, message: `"${label}": every row of a product with options needs a size or colour`, level: "error" });
      continue;
    }
    const base = Math.min(...g.rows.map((x) => x.priceCents));
    const variants = withOptions.slice(0, MAX_VARIANTS).map((x) => ({ ...optionOf(x), priceAdjustCents: x.priceCents - base }));
    if (withOptions.length > MAX_VARIANTS) issues.push({ item: `row ${first.line}`, message: `Only the first ${MAX_VARIANTS} options were imported`, level: "warning" });

    const urls = first.get("image_urls").split("|").map((u) => u.trim()).filter(Boolean);
    const imageUrls = urls.map(cleanImageUrl).filter((u): u is string => !!u);
    if (imageUrls.length < urls.length) issues.push({ item: `row ${first.line}`, message: "Photo addresses must start with https:// — some were skipped", level: "warning" });
    if (imageUrls.length > MAX_IMAGES_PER_PRODUCT) issues.push({ item: `row ${first.line}`, message: `Only the first ${MAX_IMAGES_PER_PRODUCT} photos were imported`, level: "warning" });

    const cond = first.get("condition").toLowerCase();
    const condition = CONDITIONS.get(cond.replace(/[-_]/g, " ")) ?? CONDITIONS.get(cond) ?? "NEW";
    const description = first.get("description") || undefined;
    const match = mapTaxonomy([first.get("category_slug"), first.get("category"), label], description);
    const audience = AUDIENCES.get(first.get("audience").toLowerCase());
    if (audience) match.audience = audience;
    const ml = first.get("content_ml"), gr = first.get("content_g");
    items.push(refineItem({
      externalId: g.key.slice(0, 80),
      label: `row ${first.line} (${label})`,
      name: label,
      description,
      category: legacyCategory(match),
      match,
      brand: first.get("brand").slice(0, 60) || undefined,
      content: !variants.length && (ml || gr) ? { amount: Number((ml || gr).replace(",", ".")), unit: ml ? "ml" : "g" } : null,
      condition,
      isSecondHand: condition !== "NEW" || match.secondHand,
      tags: [],
      priceCents: base,
      stockQuantity: variants.length ? variants.reduce((s, v) => s + v.stock, 0) : g.rows[0].stock,
      variants,
      imageUrls: imageUrls.slice(0, MAX_IMAGES_PER_PRODUCT),
      gtin: validGtin(first.get("gtin")),
    }));
  }
  return { items, issues, skipped, groups: groups.size };
}
