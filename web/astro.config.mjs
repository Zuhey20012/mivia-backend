// @ts-check
import { defineConfig } from "astro/config";

// The public address of the site. Canonical URLs, hreflang links, Open Graph images and the sitemap are
// built from it, so set SITE_URL on the build (Render → Environment) once the real domain is chosen.
// Until then it defaults to the Render static-site address this README suggests.
const site = (process.env.SITE_URL || "https://malvoya-web.onrender.com").replace(/\/+$/, "");

export default defineConfig({
  site,
  output: "static",
  trailingSlash: "always",
  build: {
    format: "directory",
    // Small pages: keep the CSS inline so the first paint needs no extra request.
    inlineStylesheets: "always",
  },
  compressHTML: true,
  // No prefetching, no client router: plain links, no JavaScript needed to move around.
  prefetch: false,
  devToolbar: { enabled: false },
  image: {
    // Images are optimised at build time with sharp (astro:assets).
    responsiveStyles: false,
  },
});
