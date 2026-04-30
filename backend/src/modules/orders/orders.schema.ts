import { z } from "zod";

export const createOrderSchema = z.object({
  storeId:         z.number().int().positive(),
  deliveryAddress: z.string().min(5),
  deliveryLat:     z.number().optional(),
  deliveryLng:     z.number().optional(),
  notes:           z.string().max(500).optional(),
  items: z.array(z.object({
    productId: z.number().int().positive(),
    variantId: z.number().int().positive().optional(),
    quantity:  z.number().int().min(1),
  })).min(1),
});

export const createRentalSchema = z.object({
  startDate: z.string().datetime(),
  endDate:   z.string().datetime(),
  deliveryAddress: z.string().min(5),
  items: z.array(z.object({
    productId: z.number().int().positive(),
    variantId: z.number().int().positive().optional(),
    quantity:  z.number().int().min(1),
  })).min(1),
}).refine(d => new Date(d.endDate) > new Date(d.startDate), {
  message: "endDate must be after startDate",
}).refine(d => new Date(d.startDate) > new Date(), {
  message: "startDate must be in the future",
});

export const createReturnSchema = z.object({
  orderId:  z.number().int().positive().optional(),
  rentalId: z.number().int().positive().optional(),
  reason:   z.enum(["WRONG_ITEM","DAMAGED_ON_ARRIVAL","NOT_AS_DESCRIBED","CHANGED_MIND","RENTAL_RETURN","OTHER"]),
  conditionNote: z.string().max(500).optional(),
}).refine(d => d.orderId || d.rentalId, {
  message: "Must provide either orderId or rentalId",
}).refine(d => !(d.orderId && d.rentalId), {
  message: "Cannot provide both orderId and rentalId",
});

export const updateReturnStatusSchema = z.object({
  status:         z.enum(["APPROVED","IN_TRANSIT","RECEIVED","REFUNDED","REJECTED"]),
  conditionNote:  z.string().max(500).optional(),
  refundCents:    z.number().int().min(0).optional(),
  damageDedCents: z.number().int().min(0).optional(),
});
