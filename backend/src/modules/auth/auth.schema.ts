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
  // Terms of service + privacy policy acceptance is required to create an account
  acceptTerms: z.literal(true).optional(),
});

export const loginSchema = z.object({
  email:    identifier,
  password: z.string().min(1).max(72),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput    = z.infer<typeof loginSchema>;
