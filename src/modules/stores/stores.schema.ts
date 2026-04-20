import { z } from "zod";

export const createStoreSchema = z.object({
  name:          z.string().min(2).max(100),
  description:   z.string().max(1000).optional(),
  category:      z.enum(["APPAREL","COSMETICS","THRIFT","ACCESSORIES","HOME_DECOR","HANDMADE","ECO_FRIENDLY","OTHER"]),
  isHomeBased:   z.boolean().default(false),
  isEcoFriendly: z.boolean().default(false),
  address:       z.string().optional(),
  latitude:      z.number().optional(),
  longitude:     z.number().optional(),
  phone:         z.string().optional(),
  email:         z.string().email().optional(),
});

export const updateStoreSchema = createStoreSchema.partial();

export const storeQuerySchema = z.object({
  category:    z.string().optional(),
  isHomeBased: z.string().optional(),
  search:      z.string().optional(),
  page:        z.string().default("1"),
  limit:       z.string().default("20"),
});
