import { z } from "zod";

// "email" accepts either an email address or a phone number (the apps use one field for both).
const identifier = z.string().trim().min(3).max(254);

export const registerSchema = z.object({
  name:  z.string().trim().min(1).max(80),
  email: identifier,
  phone: z.string().trim().max(20).optional(),
  // bcrypt only uses the first 72 bytes
  password: z.string().min(8, "Password must be at least 8 characters").max(72),
  role:  z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
  // The agreement for the role (customer terms / seller terms / courier agreement); required for stores and
  // couriers. When given, the time and the version of the text are stored on the account.
  acceptTerms: z.literal(true).optional(),
  // "I am 18 or older" (since 2.16.0): required for every role. The customer terms, seller terms and courier agreement
  // all require the account holder to be an adult; the time is stored as User.ageConfirmedAt.
  ageConfirmed: z.boolean().optional(),
}).superRefine((d, ctx) => {
  if ((d.role === "VENDOR" || d.role === "COURIER") && d.acceptTerms !== true) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom, path: ["acceptTerms"],
      message: d.role === "VENDOR" ? "Accept the Seller Terms to create a store account" : "Accept the Courier Agreement to create a courier account",
    });
  }
  if (d.ageConfirmed !== true) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["ageConfirmed"], message: AGE_REQUIRED_MESSAGE });
  }
});

/** Shown when /auth/register is called without ageConfirmed: true (both languages: no account, no locale yet). */
export const AGE_REQUIRED_MESSAGE =
  "Confirm that you are 18 or older to create an account. / Vahvista, että olet vähintään 18-vuotias, jotta voit luoda tilin.";

export const loginSchema = z.object({
  email:    identifier,
  password: z.string().min(1).max(72),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput    = z.infer<typeof loginSchema>;
