import { Router, Request, Response } from "express";

/**
 * What the apps check on start-up: is this build still supported, and is Malvoya in maintenance?
 * Set on Render without a new release:
 *   MIN_BUILD_CUSTOMER / MIN_BUILD_STORE / MIN_BUILD_COURIER — older builds are asked to update
 *   MAINTENANCE_MESSAGE — when set, the apps show it instead of letting people order
 */
const APPS = {
  customer: { env: "MIN_BUILD_CUSTOMER", packageId: "com.malvoya.customer" },
  store: { env: "MIN_BUILD_STORE", packageId: "com.malvoya.vendor" },
  courier: { env: "MIN_BUILD_COURIER", packageId: "com.malvoya.courier" },
} as const;
type AppName = keyof typeof APPS;

export function appConfigFor(app: AppName, build: number | null) {
  const minBuild = Math.max(0, Number(process.env[APPS[app].env]) || 0);
  const message = (process.env.MAINTENANCE_MESSAGE || "").trim();
  return {
    minBuild,
    updateRequired: build !== null && build < minBuild,
    storeUrl: `https://play.google.com/store/apps/details?id=${APPS[app].packageId}`,
    maintenance: { active: message.length > 0, message: message || null },
  };
}

export function appConfigSummary() {
  return Object.fromEntries((Object.keys(APPS) as AppName[]).map((a) => [a, appConfigFor(a, null)]));
}

const router = Router();

router.get("/app-config", (req: Request, res: Response) => {
  const app = String(req.query.app || "") as AppName;
  if (!(app in APPS)) return res.status(400).json({ ok: false, error: "Unknown app" });
  const build = Number.parseInt(String(req.query.build ?? ""), 10);
  res.set("Cache-Control", "no-store");
  res.json({ ok: true, ...appConfigFor(app, Number.isFinite(build) ? build : null) });
});

export default router;
