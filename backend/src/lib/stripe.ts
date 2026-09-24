import Stripe from "stripe";
import { env } from "../config/env";

const createClient = (key: string) => new Stripe(key, { apiVersion: "2023-10-16" as any });
let client: ReturnType<typeof createClient> | null = null;

/** Lazily created so the API can boot (and serve browsing) before Stripe keys are configured. */
export function getStripe() {
  if (!env.stripeSecretKey) {
    throw Object.assign(new Error("Payments are not configured"), { status: 503 });
  }
  if (!client) client = createClient(env.stripeSecretKey);
  return client;
}
