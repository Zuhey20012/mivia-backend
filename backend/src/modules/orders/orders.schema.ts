import { z } from "zod";

// The basket and how it reaches the customer; shared by the quote and the order
const checkoutSchema = z.object({
  storeId:         z.number().int().positive(),
  // DELIVERY (default): a courier brings it. PICKUP ("Reserve & collect"): the customer collects it from the
  // store with a 6-digit code, no delivery fee, no courier and no tip.
  fulfilment:      z.enum(["DELIVERY", "PICKUP"]).default("DELIVERY"),
  deliveryLat:     z.number().min(-90).max(90).optional(),
  deliveryLng:     z.number().min(-180).max(180).optional(),
  // Optional courier tip in cents (max 20 €); it is added to the total and paid to the courier in full
  tipCents:        z.number().int().min(0).max(2000).optional(),
  // Optional promo code or a friend's invite code (platform-funded discount); an unusable code is refused with 409
  promoCode:       z.string().trim().max(40).optional(),
  // Scheduled delivery (DELIVERY only): one of the platform slots (Finnish time), today or tomorrow.
  // Absent = as soon as possible.
  deliverySlot:    z.object({
    date:  z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use YYYY-MM-DD"),
    start: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM"),
    end:   z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM"),
  }).strict().optional(),
  items: z.array(z.object({
    productId: z.number().int().positive(),
    variantId: z.number().int().positive().optional(),
    quantity:  z.number().int().min(1).max(20),
  })).min(1).max(50),
});

/** A pickup order is collected at the store, so it has no delivery time slot. */
function slotOnlyForDelivery(d: { fulfilment: string; deliverySlot?: unknown }, ctx: z.RefinementCtx) {
  if (d.fulfilment === "PICKUP" && d.deliverySlot) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["deliverySlot"], message: "Pickup orders have no delivery time" });
  }
}

export const createOrderSchema = checkoutSchema.extend({
  // Required for delivery; not used for pickup
  deliveryAddress: z.string().trim().min(5).max(300).optional(),
  notes:           z.string().max(500).optional(),
}).superRefine((d, ctx) => {
  if (d.fulfilment === "DELIVERY" && !d.deliveryAddress) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["deliveryAddress"], message: "Enter a delivery address" });
  }
  slotOnlyForDelivery(d, ctx);
});

// Exact price before payment: the same basket as an order, without the address
export const quoteOrderSchema = checkoutSchema.superRefine(slotOnlyForDelivery);

export const createRentalSchema = z.object({
  startDate: z.string().datetime(),
  endDate:   z.string().datetime(),
  deliveryAddress: z.string().trim().min(5).max(300),
  items: z.array(z.object({
    productId: z.number().int().positive(),
    variantId: z.number().int().positive().optional(),
    quantity:  z.number().int().min(1).max(10),
  })).min(1).max(20),
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
  // Hygiene-sealed items returned under the right of withdrawal: the customer says whether the seal is unbroken (2.12)
  sealIntact: z.boolean().optional(),
  // Only some of the items (order lines and how many of each); without it the whole order (what is left of it)
  items: z.array(z.object({
    orderItemId: z.number().int().positive(),
    quantity:    z.number().int().min(1).max(100),
  })).min(1).max(50).optional(),
}).refine(d => d.orderId || d.rentalId, {
  message: "Must provide either orderId or rentalId",
}).refine(d => !(d.orderId && d.rentalId), {
  message: "Cannot provide both orderId and rentalId",
});

export const updateReturnStatusSchema = z.object({
  status:         z.enum(["APPROVED","IN_TRANSIT","RECEIVED","REFUNDED","REJECTED"]),
  conditionNote:  z.string().max(500).optional(),
  // The store's reason or notes, shown to the customer; required when the return is rejected
  storeNote:      z.string().trim().max(500).optional(),
  refundCents:    z.number().int().min(0).optional(),
  damageDedCents: z.number().int().min(0).optional(),
});

export const updateOrderStatusSchema = z.object({
  status: z.enum(["CONFIRMED", "PROCESSING", "SHIPPED", "DELIVERED", "CANCELLED"]),
  // Only used when the store cancels: its reason, stored as the cancel reason and shown to the customer
  reason: z.string().trim().max(200).optional(),
});

// The courier is at the address and cannot hand the order over
export const deliveryProblemSchema = z.object({
  reason: z.enum(["CUSTOMER_UNAVAILABLE", "WRONG_ADDRESS", "OTHER"]),
  note: z.string().trim().max(300).optional(),
});

// The store types in the customer's 6-digit pickup code at the counter
export const collectOrderSchema = z.object({
  code: z.string().trim().min(1).max(20),
});
