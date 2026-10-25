export type Lang = "fi" | "en";

/** Every page in both languages. Finnish lives at the root, English under /en/. */
export const ROUTES = {
  home: { fi: "/", en: "/en/" },
  sell: { fi: "/kauppiaille/", en: "/en/sell/" },
  deliver: { fi: "/lahetiksi/", en: "/en/deliver/" },
  help: { fi: "/apua/", en: "/en/help/" },
  download: { fi: "/lataa/", en: "/en/download/" },
  legal: { fi: "/ehdot/", en: "/en/legal/" },
  cookies: { fi: "/evasteet/", en: "/en/cookies/" },
} as const;

export type RouteKey = keyof typeof ROUTES;
export type Alternates = Record<Lang, string>;

export const r = (key: RouteKey, lang: Lang) => ROUTES[key][lang];

/** Help articles: one stable key, a slug per language. */
export const HELP_ARTICLES = [
  { key: "ordering", fi: "tilaaminen", en: "ordering" },
  { key: "delivery", fi: "toimitus-ja-nouto", en: "delivery-and-pickup" },
  { key: "returns", fi: "palautukset", en: "returns" },
  { key: "refunds", fi: "hyvitykset", en: "refunds" },
  { key: "account", fi: "tili-ja-salasana", en: "account-and-password" },
  { key: "privacy", fi: "tietosuoja-ja-tiedot", en: "privacy-and-your-data" },
  { key: "contact", fi: "ota-yhteytta", en: "contact" },
] as const;

export type HelpKey = (typeof HELP_ARTICLES)[number]["key"];

export function helpPath(key: HelpKey, lang: Lang): string {
  const a = HELP_ARTICLES.find((x) => x.key === key);
  if (!a) throw new Error(`Unknown help article ${key}`);
  return `${ROUTES.help[lang]}${a[lang]}/`;
}

export const helpAlternates = (key: HelpKey): Alternates => ({ fi: helpPath(key, "fi"), en: helpPath(key, "en") });

export const t = <T,>(lang: Lang, fi: T, en: T): T => (lang === "fi" ? fi : en);
