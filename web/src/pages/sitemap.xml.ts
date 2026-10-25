import type { APIRoute } from "astro";
import { HELP_ARTICLES, ROUTES, helpAlternates, type Alternates } from "../i18n/routes";

/** sitemap.xml with hreflang alternates for every page in both languages. */
export const GET: APIRoute = ({ site }) => {
  const base = (site?.href ?? "https://malvoya-web.onrender.com/").replace(/\/$/, "");
  const pages: Alternates[] = [...Object.values(ROUTES), ...HELP_ARTICLES.map((a) => helpAlternates(a.key))];
  const today = new Date().toISOString().slice(0, 10);
  const url = (alt: Alternates, lang: "fi" | "en") => `  <url>
    <loc>${base}${alt[lang]}</loc>
    <lastmod>${today}</lastmod>
    <xhtml:link rel="alternate" hreflang="fi" href="${base}${alt.fi}"/>
    <xhtml:link rel="alternate" hreflang="en" href="${base}${alt.en}"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="${base}${alt.fi}"/>
  </url>`;
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${pages.flatMap((p) => [url(p, "fi"), url(p, "en")]).join("\n")}
</urlset>
`;
  return new Response(body, { headers: { "Content-Type": "application/xml; charset=utf-8" } });
};
