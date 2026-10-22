// Loaded first (before express and http are required) so Sentry's automatic instrumentation can hook into them.
// Does nothing unless SENTRY_DSN is set.
import "dotenv/config";
import { initSentry } from "./lib/sentry";

initSentry();
