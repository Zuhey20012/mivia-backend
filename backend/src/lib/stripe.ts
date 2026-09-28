import Stripe from "stripe";
import { env } from "../config/env";

// STRIPE_API_BASE points the client at a local stripe-mock in tests (e.g. http://localhost:12111)
const mock = process.env.STRIPE_API_BASE ? new URL(process.env.STRIPE_API_BASE) : null;
const createClient = (key: string) =>
  new Stripe(key, {
    apiVersion: "2023-10-16" as any,
    ...(mock ? { host: mock.hostname, port: Number(mock.port), protocol: mock.protocol.replace(":", "") as "http" | "https" } : {}),
  });
let client: ReturnType<typeof createClient> | null = null;

/** Lazily created so the API can boot (and serve browsing) before Stripe keys are configured. */
export function getStripe() {
  if (!env.stripeSecretKey) {
    throw Object.assign(new Error("Payments are not configured"), { status: 503 });
  }
  if (!client) client = createClient(env.stripeSecretKey);
  return client;
}
