import { z } from "zod";

export const registerSchema = z.object({
  name:  z.string().min(1).max(80),
  email: z.string().min(1),
  phone: z.string().optional(),
  password: z.string().min(6),
  role:  z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
});

export const loginSchema = z.object({
  email:    z.string().min(1),
  password: z.string().min(1),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput    = z.infer<typeof loginSchema>;
