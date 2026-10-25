/**
 * Everything the owner may need to change in one place: links to the live API's legal pages and the
 * app-store listings. Nothing here is secret.
 */

export const SITE_NAME = "Malvoya";

/** The live API (Render, Frankfurt). Its public pages are the legal texts in force and the recalls list. */
export const API_BASE = "https://malvoya-api-eu.onrender.com";

export const LEGAL = {
  terms: `${API_BASE}/legal/terms`,
  privacy: `${API_BASE}/legal/privacy`,
  sellers: `${API_BASE}/legal/sellers`,
  couriers: `${API_BASE}/legal/couriers`,
  deleteAccount: `${API_BASE}/legal/delete-account`,
  recalls: `${API_BASE}/recalls`,
} as const;

export type AppKey = "customer" | "store" | "courier";

export type StoreLink = {
  /** The listing address. Shown as a link only when `live` is true. */
  url: string;
  /** Set to true only after the listing is published and the URL opens for everyone. */
  live: boolean;
};

export type AppInfo = {
  key: AppKey;
  name: string;
  androidId: string;
  googlePlay: StoreLink;
  appStore: StoreLink;
};

/**
 * The three apps. Google Play addresses follow the application IDs. They are NOT live yet: the site shows
 * "coming soon" instead of a link until `live` is switched to true. The App Store has no listing at all yet;
 * add its address (https://apps.apple.com/fi/app/…/id…) when Apple publishes it.
 */
export const APPS: Record<AppKey, AppInfo> = {
  customer: {
    key: "customer",
    name: "Malvoya",
    androidId: "com.malvoya.customer",
    googlePlay: { url: "https://play.google.com/store/apps/details?id=com.malvoya.customer", live: false },
    appStore: { url: "", live: false },
  },
  store: {
    key: "store",
    name: "Malvoya Store",
    androidId: "com.malvoya.vendor",
    googlePlay: { url: "https://play.google.com/store/apps/details?id=com.malvoya.vendor", live: false },
    appStore: { url: "", live: false },
  },
  courier: {
    key: "courier",
    name: "Malvoya Courier",
    androidId: "com.malvoya.courier",
    googlePlay: { url: "https://play.google.com/store/apps/details?id=com.malvoya.courier", live: false },
    appStore: { url: "", live: false },
  },
};

/** The link a "get the app" button should use: the live Play listing, or our own download page. */
export function appHref(app: AppKey, downloadPage: string): string {
  const play = APPS[app].googlePlay;
  return play.live && play.url ? play.url : downloadPage;
}

/**
 * Courier pay settings as set in the backend today (backend/src/config/env.ts defaults, the same values
 * as backend/.env.example). If the values on Render are changed, update them here too.
 */
export const COURIER_PAY = {
  baseCents: 450,
  perKmCents: 110,
  minCents: 650,
  roadFactor: 1.3,
  approachFreeKm: 2,
  approachPerKmCents: 50,
  approachMaxKm: 7.5,
  waitFreeMinutes: 5,
  waitPerMinCents: 20,
  waitMaxCents: 400,
  dispatchRadiusKm: 7.5,
  noticeDays: 15,
} as const;
