import { z } from "zod";
import { openingHoursSchema } from "../../utils/openingHours";
import { isValidYTunnus } from "./businessCheck";

/**
 * Stores are in Finland (2.17): coordinates outside its bounding box (incl. Åland) are refused, so a far-away pin
 * cannot be used to place a "local" store or inflate courier pay.
 */
export const FINLAND_BBOX = { minLat: 59.3, maxLat: 70.2, minLng: 19.0, maxLng: 31.7 };
const lat = z.number().min(FINLAND_BBOX.minLat, "The store must be in Finland").max(FINLAND_BBOX.maxLat, "The store must be in Finland");
const lng = z.number().min(FINLAND_BBOX.minLng, "The store must be in Finland").max(FINLAND_BBOX.maxLng, "The store must be in Finland");

// Availability: pause switch and weekly opening hours (Finnish time); null clears the hours (always open)
const availability = {
  acceptingOrders: z.boolean().optional(),
  openingHours:    openingHoursSchema.nullable().optional(),
};

export const createStoreSchema = z.object({
  name:          z.string().min(2).max(100),
  description:   z.string().max(1000).optional(),
  category:      z.string().transform((val) => {
    const raw = (val || "").toString().toUpperCase().trim().replace(/\s+/g, '_');
    if (raw === 'SKINCARE') return 'COSMETICS' as const;
    if (raw === 'BOUTIQUES' || raw === 'CLOTHING') return 'APPAREL' as const;
    if (raw === 'HOME_BASED') return 'HOME_DECOR' as const;
    // ECO_FRIENDLY was removed in 2.12.0 (a generic environmental claim): older app builds sending it get OTHER
    const valid = ["APPAREL","COSMETICS","THRIFT","ACCESSORIES","HOME_DECOR","HANDMADE","OTHER"];
    if (valid.includes(raw)) return raw as any;
    return "OTHER" as const;
  }),
  isHomeBased:   z.boolean().default(false),
  address:       z.string().optional(),
  latitude:      lat.optional(),
  longitude:     lng.optional(),
  phone:         z.string().optional(),
  email:         z.string().email().optional(),
  logoUrl:       z.string().url().startsWith("https://").optional(),
  bannerUrl:     z.string().url().startsWith("https://").optional(),
  // Business sellers give their Y-tunnus (format 1234567-8); private people selling their own items do not
  sellerType:    z.enum(["BUSINESS", "PRIVATE"]).optional(), // older app builds do not send it
  businessId:    z.string().trim().regex(/^\d{7}-\d$/, "Y-tunnus format is 1234567-8")
    .refine(isValidYTunnus, "This Y-tunnus is not valid: check the last digit").optional(),
  prepMinutes:   z.number().int().min(0).max(120).optional(),
  ...availability,
}).refine((d) => d.sellerType !== "BUSINESS" || !!d.businessId, {
  message: "Business sellers must give their Y-tunnus",
  path: ["businessId"],
});

export const updateStoreSchema = z.object({
  name:        z.string().min(2).max(100).optional(),
  description: z.string().max(1000).optional(),
  isHomeBased: z.boolean().optional(),
  address:     z.string().optional(),
  latitude:    lat.optional(),
  longitude:   lng.optional(),
  phone:       z.string().optional(),
  email:       z.string().email().optional(),
  logoUrl:     z.string().url().startsWith("https://").optional(),
  bannerUrl:   z.string().url().startsWith("https://").optional(),
  prepMinutes: z.number().int().min(0).max(120).optional(),
  ...availability,
});

export const storeQuerySchema = z.object({
  category:    z.string().optional(),
  isHomeBased: z.string().optional(),
  search:      z.string().optional(),
  page:        z.string().default("1"),
  limit:       z.string().default("20"),
  lat:         z.string().optional(),
  lng:         z.string().optional(),
});
