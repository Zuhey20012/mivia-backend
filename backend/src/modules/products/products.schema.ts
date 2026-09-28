import { z } from "zod";

const variantSchema = z.object({
  id:               z.number().int().positive().optional(), // present when editing an existing option
  size:             z.string().trim().max(20).optional(),
  color:            z.string().trim().max(40).optional(),
  sku:              z.string().trim().max(64).optional(),
  stock:            z.number().int().min(0).max(10000).default(1),
  priceAdjustCents: z.number().int().min(-100000).max(100000).default(0),
}).refine((v) => !!(v.size || v.color), { message: "Each option needs a size or a colour" });

const baseProductSchema = z.object({
  name:          z.string().trim().min(2).max(200),
  description:   z.string().trim().max(2000).optional(),
  category:      z.string().trim().min(1).max(60),
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
  isEcoFriendly: z.boolean().default(false),
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
  isEcoFriendly:z.string().optional(),
  isSecondHand: z.string().optional(),
  search:       z.string().max(100).optional(),
  minPrice:     z.string().optional(),
  maxPrice:     z.string().optional(),
  condition:    z.string().optional(),
  page:         z.string().default("1"),
  limit:        z.string().default("20"),
});

export const searchQuerySchema = z.object({
  q:         z.string().trim().max(100).optional(),
  category:  z.string().trim().max(60).optional(),
  size:      z.string().trim().max(20).optional(),
  color:     z.string().trim().max(40).optional(),
  condition: z.enum(["NEW", "LIKE_NEW", "GOOD", "FAIR", "POOR"]).optional(),
  secondHand:z.enum(["true", "false"]).optional(),
  minPrice:  z.coerce.number().int().min(0).optional(),
  maxPrice:  z.coerce.number().int().min(0).optional(),
  sort:      z.enum(["relevance", "newest", "price_asc", "price_desc", "rating"]).default("relevance"),
  page:      z.coerce.number().int().min(1).max(500).default(1),
  limit:     z.coerce.number().int().min(1).max(50).default(24),
});
