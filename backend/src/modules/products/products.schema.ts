import { z } from "zod";
import { COLOUR_FAMILIES, CONTENT_UNITS, FINISHES, SHADE_FAMILIES, UNDERTONES } from "../catalog/attributes";

const MEASUREMENTS = ["chest", "bust", "waist", "hips", "insideLeg", "height", "neck", "length", "chestWidth", "sleeve", "footLengthCm", "headCircumferenceCm", "innerDiameterMm"] as const;

/** GS1 check digit (GTIN-8/12/13/14). */
export function gtinCheckDigitOk(v: string) {
  if (!/^\d{8}$|^\d{12,14}$/.test(v)) return false;
  const digits = v.split("").map(Number);
  const check = digits.pop()!;
  const sum = digits.reverse().reduce((s, d, i) => s + d * (i % 2 === 0 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10 === check;
}

const variantSchema = z.object({
  id:               z.number().int().positive().optional(), // present when editing an existing option
  size:             z.string().trim().max(20).optional(),
  color:            z.string().trim().max(40).optional(),
  sku:              z.string().trim().max(64).optional(),
  stock:            z.number().int().min(0).max(10000).default(1),
  priceAdjustCents: z.number().int().min(-100000).max(100000).default(0),
  // Option data (2.12): colour family, shade (makeup/nails), measurements in cm, content per option (unit price)
  colourFamily:     z.enum(COLOUR_FAMILIES).nullable().optional(),
  shadeName:        z.string().trim().max(40).nullable().optional(),
  shadeHex:         z.string().regex(/^#[0-9A-Fa-f]{6}$/, "Use #RRGGBB").nullable().optional(),
  shadeFamily:      z.enum(SHADE_FAMILIES).nullable().optional(),
  undertone:        z.enum(UNDERTONES).nullable().optional(),
  finish:           z.enum(FINISHES).nullable().optional(),
  measurements:     z.record(z.enum(MEASUREMENTS), z.number().positive().max(400)).optional(),
  contentAmount:    z.number().positive().max(100000).nullable().optional(),
  contentUnit:      z.enum(CONTENT_UNITS).nullable().optional(),
}).refine((v) => !!(v.size || v.color || v.shadeName || v.contentAmount), { message: "Each option needs a size, a colour, a shade or a content" });

const i18nWarnings = z.object({
  fi: z.string().trim().max(2000).optional(),
  sv: z.string().trim().max(2000).optional(),
  en: z.string().trim().max(2000).optional(),
}).strict();

const baseProductSchema = z.object({
  name:          z.string().trim().min(2).max(200),
  description:   z.string().trim().max(2000).optional(),
  // Legacy free text (older app builds): mapped onto the taxonomy when no categorySlug is given
  category:      z.string().trim().min(1).max(60).optional(),
  // 2.12: a subcategory slug from GET /categories (null clears it)
  categorySlug:  z.string().trim().max(60).nullable().optional(),
  audience:      z.enum(["WOMEN", "MEN", "KIDS", "UNISEX"]).optional(),
  attributes:    z.record(z.any()).optional(),
  hygieneSealed: z.boolean().optional(),
  contentAmount: z.number().positive().max(100000).nullable().optional(),
  contentUnit:   z.enum(CONTENT_UNITS).nullable().optional(),
  // Product safety (GPSR Art. 19)
  manufacturerId:      z.number().int().positive().nullable().optional(),
  responsiblePersonId: z.number().int().positive().nullable().optional(),
  productModel:  z.string().trim().max(80).nullable().optional(),
  batchOrSerial: z.string().trim().max(80).nullable().optional(),
  gtin:          z.string().trim().refine((v) => v === "" || gtinCheckDigitOk(v), "Not a valid EAN/GTIN (check digit)").nullable().optional(),
  warnings:      i18nWarnings.nullable().optional(),
  noWarnings:    z.boolean().optional(),
  safetyImages:  z.array(z.string().url().startsWith("https://")).max(6).optional(),
  certificateIds:z.array(z.number().int().positive()).max(20).optional(),

  condition:     z.enum(["NEW", "LIKE_NEW", "GOOD", "FAIR", "POOR"]).default("NEW"),
  tags:          z.array(z.string().trim().max(40)).max(20).default([]),
  images:        z.array(z.string().url().startsWith("https://")).max(10).default([]),
  canBeSold:     z.boolean().default(true),
  salePriceCents:z.number().int().positive().max(10_000_000).optional(),
  canBeRented:   z.boolean().default(false),
  rentalDayCents:z.number().int().positive().optional(),
  depositCents:  z.number().int().positive().optional(),
  stockQuantity: z.number().int().min(0).max(10000).default(1),
  isAvailable:   z.boolean().optional(),
  isHandmade:    z.boolean().default(false),
  isSecondHand:  z.boolean().default(false),
  variants:      z.array(variantSchema).max(60).default([]),
});

export const createProductSchema = baseProductSchema
  .refine((d) => (d.canBeSold ? !!d.salePriceCents : true), { message: "salePriceCents required when canBeSold is true" })
  .refine((d) => (d.canBeRented ? !!d.rentalDayCents && !!d.depositCents : true), {
    message: "rentalDayCents and depositCents required when canBeRented is true",
  });

// Partial updates: .partial() wraps every field in ZodOptional, which returns undefined for a
// missing field before any inner default runs, so left-out fields keep their stored value.
export const updateProductSchema = baseProductSchema.partial();

export const productQuerySchema = z.object({
  canBeSold:    z.string().optional(),
  canBeRented:  z.string().optional(),
  isSecondHand: z.string().optional(),
  search:       z.string().max(100).optional(),
  minPrice:     z.string().optional(),
  maxPrice:     z.string().optional(),
  condition:    z.string().optional(),
  category:     z.string().max(60).optional(),
  page:         z.string().default("1"),
  limit:        z.string().default("20"),
});

const list = z.string().trim().max(400).optional();

export const searchQuerySchema = z.object({
  q:         z.string().trim().max(100).optional(),
  // A category slug (descendants included) or, for older app builds, the legacy free-text category
  category:  z.string().trim().max(60).optional(),
  audience:  z.enum(["WOMEN", "MEN", "KIDS", "UNISEX", "women", "men", "kids", "unisex"]).optional(),
  size:      z.string().trim().max(20).optional(),
  color:     z.string().trim().max(40).optional(),
  condition: z.enum(["NEW", "LIKE_NEW", "GOOD", "FAIR", "POOR"]).optional(),
  secondHand:z.enum(["true", "false"]).optional(),
  // Removed in 2.12.0 (a generic environmental claim): accepted and ignored so older app builds keep working
  eco:       z.any().optional(),
  handmade:  z.enum(["true"]).optional(),
  storeId:   z.coerce.number().int().positive().optional(),
  minPrice:  z.coerce.number().int().min(0).optional(),
  maxPrice:  z.coerce.number().int().min(0).optional(),
  // Attribute filters (comma-separated values = any of them); also as attr[key]=value
  colourFamily: list, shadeFamily: list, undertone: list, finish: list, skinType: list, hairType: list,
  concentration: list, metal: list, fibre: list, brand: list, certificate: list, productType: list,
  attr:      z.record(z.string().max(400)).optional(),
  sort:      z.enum(["relevance", "newest", "price_asc", "price_desc", "rating"]).default("relevance"),
  page:      z.coerce.number().int().min(1).max(500).default(1),
  limit:     z.coerce.number().int().min(1).max(50).default(24),
});

/** The named attribute filters of the search (the rest come as attr[key]). */
export const NAMED_FILTERS = ["colourFamily", "shadeFamily", "undertone", "finish", "skinType", "hairType", "concentration", "metal", "fibre", "brand", "productType"] as const;
