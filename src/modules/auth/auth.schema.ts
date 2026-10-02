import { z } from "zod";

export const registerSchema = z.object({
  name:  z.string().min(2).max(80),
  email: z.string().email(),
  phone: z.string().optional(),
  password: z.string().min(8),
  role:  z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
});

export const loginSchema = z.object({
  email:    z.string().email(),
  password: z.string().min(1),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

// Body for Firebase sign-in: the ID token from FirebaseUser.getIdToken() on the client.
// name/role are only used when the call creates a new account.
export const firebaseSignInSchema = z.object({
  idToken: z.string().min(1),
  name:    z.string().min(2).max(80).optional(),
  role:    z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
});

export const firebaseLinkSchema = z.object({
  idToken: z.string().min(1),
});

export type RegisterInput       = z.infer<typeof registerSchema>;
export type LoginInput          = z.infer<typeof loginSchema>;
export type FirebaseSignInInput = z.infer<typeof firebaseSignInSchema>;
