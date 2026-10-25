# Malvoya public website (`web/`)

The public site for Malvoya's three audiences, in Finnish (at `/`) and English (at `/en/`):

| Page | Finnish | English |
|---|---|---|
| Home (shoppers) | `/` | `/en/` |
| For shops | `/kauppiaille/` | `/en/sell/` |
| For couriers | `/lahetiksi/` | `/en/deliver/` |
| Help centre + 7 articles | `/apua/`, `/apua/<slug>/` | `/en/help/`, `/en/help/<slug>/` |
| Download | `/lataa/` | `/en/download/` |
| Legal (links to the live API pages) | `/ehdot/` | `/en/legal/` |
| Cookies (none) | `/evasteet/` | `/en/cookies/` |
| Not found (bilingual) | `/404.html` | |

Plus `sitemap.xml` (with hreflang alternates) and `robots.txt`, both generated at build time.

It is a static [Astro](https://astro.build) site: plain HTML and CSS, no framework on the client, no cookies, no analytics, no third-party requests. The only JavaScript is a few lines that close the mobile menu on Escape (the menu itself is a native `<details>` and works without it).

## Requirements

Node.js 22.12 or newer (`.node-version` says `22`, which Render also reads). Dependencies are pinned to exact versions in `package.json` and `package-lock.json`.

## Commands

```bash
cd web
npm ci              # or npm install
npm run dev         # local dev server at http://localhost:4321
npm run build       # builds dist/ and then checks every internal link (fails on a broken one)
npm run preview     # serves the built dist/ at http://localhost:4321
npm run check       # TypeScript and Astro diagnostics
```

`npm run build` = `astro build` + `scripts/check-links.mjs`, which checks every internal `href`/`src`/`srcset`, every `#anchor`, and every URL in the sitemap, and lists the external links (the live legal pages) without fetching them.

## Where things live

| Path | What |
|---|---|
| `src/config/site.ts` | **The owner's settings:** live legal URLs, app-store links and whether they are live, courier pay values |
| `src/i18n/routes.ts` | Every page in both languages; help article slugs |
| `src/views/*.astro` | One view per page, with the Finnish and English copy side by side |
| `src/content/help/{fi,en}/*.md` | Help articles (Markdown; the `key` in the front matter pairs the two languages) |
| `src/layouts/Base.astro` | `<head>`: title, description, canonical, hreflang, Open Graph/Twitter, JSON-LD Organization |
| `src/styles/global.css` | Birch Market tokens (light and dark), components, motion |
| `src/assets/screens/` | Real app screenshots (v1.7.0), optimised at build time to AVIF/WebP |
| `public/fonts/` | Bricolage Grotesque and Hanken Grotesk from the apps, subset to Latin, WOFF2, with their OFL licences |
| `public/og/` | Open Graph images (the Play feature graphics, per audience and language) |

### Things to update over time

- **Store links.** In `src/config/site.ts`, set `googlePlay.live: true` for an app once its Play listing is public; every "Get the app" button then goes straight to Google Play, and the download page shows a real link instead of "coming soon". For the App Store, add the listing URL and set `live: true`. Never set `live` before the listing opens for everyone.
- **Courier pay.** The values on `/lahetiksi/` come from `COURIER_PAY` in `src/config/site.ts`, which copies the backend defaults (`backend/src/config/env.ts`, `backend/.env.example`). If the `COURIER_*` variables on the Render API service are changed, change them here too, and publish the change on the site no later than the in-app notice (at least 15 days before it takes effect).
- **Screenshots.** Replace the files in `src/assets/screens/` with newer real screenshots (same names, or update the imports). Do not use screenshots that show invented shops, products, prices or reviews, or the old "Eco-Friendly" tile.

## Deploying as a Render Static Site

Nothing is deployed automatically from this folder. To publish it:

1. Render Dashboard → **New → Static Site** → pick the GitHub repo.
2. Settings:
   - **Branch:** `master`
   - **Root Directory:** `web`
   - **Build Command:** `npm ci && npm run build`
   - **Publish Directory:** `dist`
3. Environment: `SITE_URL` = the public address without a trailing slash (for example `https://malvoya-web.onrender.com` at first, the custom domain later). Canonical URLs, hreflang, Open Graph images, the sitemap and robots.txt are all built from it, so **rebuild after changing it**. Without `SITE_URL` the build uses `https://malvoya-web.onrender.com`.
4. Optional, under **Headers** (path `/*`): `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`. And for `/_astro/*` and `/fonts/*`: `Cache-Control: public, max-age=31536000, immutable` (those file names change whenever their content changes).

Render serves `dist/404.html` for addresses that don't exist; check it once after the first deploy by opening a made-up path.

The same as a Blueprint, **for reference only** (the repo's real `render.yaml` at the root describes the API; merge this in only if you want the site managed as code):

```yaml
services:
  - type: web
    runtime: static
    name: malvoya-web
    branch: master
    rootDir: web
    buildCommand: npm ci && npm run build
    staticPublishPath: dist
    envVars:
      - key: SITE_URL
        value: https://malvoya-web.onrender.com
    headers:
      - path: /*
        name: X-Content-Type-Options
        value: nosniff
      - path: /*
        name: Referrer-Policy
        value: strict-origin-when-cross-origin
      - path: /_astro/*
        name: Cache-Control
        value: public, max-age=31536000, immutable
      - path: /fonts/*
        name: Cache-Control
        value: public, max-age=31536000, immutable
```

## Adding a custom domain later

1. Buy or choose the domain. Note that `malvoya.com` is **not** under Malvoya's control today (see the root `CLAUDE.md`), so don't point anything at it unless that changes.
2. Render → the static site → **Settings → Custom Domains → Add**, for example `www.example.fi` and the bare `example.fi`.
3. At the domain registrar, add the DNS records Render shows (a `CNAME` for `www`, and an `A`/`ALIAS`/`ANAME` record for the bare domain). Render issues the HTTPS certificate itself once DNS resolves.
4. Set `SITE_URL` to the new address (e.g. `https://www.example.fi`) and redeploy, so canonical URLs and the sitemap use it.
5. If the apps' share links or the API's `ALLOWED_ORIGINS` should know about the new domain, that is a separate change in the backend.
6. Submit `https://<domain>/sitemap.xml` in Google Search Console.

## Accessibility, performance and privacy notes

- WCAG 2.1 AA: text contrast checked against the palette (secondary text ≥ 4.5:1 on every tile colour), visible focus rings, a skip link, landmarks, labelled navigation, alt text on every screenshot, 44 px+ touch targets, `prefers-reduced-motion` respected (scroll reveals and the floating phones switch off).
- Light and dark mode follow `prefers-color-scheme`; nothing is stored.
- Performance: CSS is inlined, no client framework, fonts are self-hosted WOFF2 subsets with `font-display: swap`, metric-matched fallbacks (so the swap doesn't shift layout) and preloads; images have fixed dimensions and AVIF/WebP variants.
- No cookies, no `localStorage`, no analytics, no external scripts, fonts or images. If that ever changes, update `/evasteet/` and `/en/cookies/` first.
