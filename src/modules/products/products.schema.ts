import { z } from "zod";

export const createProductSchema = z.object({
  name:          z.string().min(2).max(200),
  description:   z.string().max(2000).optional(),
  category:      z.string().min(1),
  condition:     z.enum(["NEW","LIKE_NEW","GOOD","FAIR","POOR"]).default("NEW"),
  tags:          z.array(z.string()).default([]),
  canBeSold:     z.boolean().default(true),
  salePriceCents:z.number().int().positive().optional(),
  canBeRented:   z.boolean().default(false),
  rentalDayCents:z.number().int().positive().optional(),
  depositCents:  z.number().int().positive().optional(),
  stockQuantity: z.number().int().min(1).default(1),
  isEcoFriendly: z.boolean().default(false),
  isHandmade:    z.boolean().default(false),
  isSecondHand:  z.boolean().default(false),
  variants:      z.array(z.object({
    size:             z.string().optional(),
    color:            z.string().optional(),
    sku:              z.string().optional(),
    stock:            z.number().int().default(1),
    priceAdjustCents: z.number().int().default(0),
  })).default([]),
}).refine(d => d.canBeSold ? !!d.salePriceCents : true, {
  message: "salePriceCents required when canBeSold is true",
}).refine(d => d.canBeRented ? !!d.rentalDayCents && !!d.depositCents : true, {
  message: "rentalDayCents and depositCents required when canBeRented is true",
});

export const updateProductSchema = (createProductSchema as any).innerType().innerType().partial();

export const productQuerySchema = z.object({
  canBeSold:    z.string().optional(),
  canBeRented:  z.string().optional(),
  isEcoFriendly:z.string().optional(),
  isSecondHand: z.string().optional(),
  search:       z.string().optional(),
  minPrice:     z.string().optional(),
  maxPrice:     z.string().optional(),
  condition:    z.string().optional(),
  page:         z.string().default("1"),
  limit:        z.string().default("20"),
});
