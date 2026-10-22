import { Router, Request, Response, NextFunction } from "express";
import { scale } from "../config/scale";

/**
 * Cache-Control for public GETs (stores, products, search, drops feed, legal and share pages). Express already sends
 * an ETag, and answers 304 when the app or a CDN sends it back (If-None-Match), so a repeat costs no body.
 *  - Anonymous requests: `public, max-age=<short>, stale-while-revalidate=<longer>`, so a CDN or the phone may reuse
 *    them briefly and refresh in the background.
 *  - Signed-in requests can carry personal fields (likes, follows, favourites, owner views): `private, no-cache`
 *    (only the user's own device may keep a copy, and must revalidate it).
 * Vary keeps per-language and per-encoding copies apart.
 */
export function publicCache(maxAge = scale.publicCacheSeconds, stale = scale.publicStaleSeconds) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (req.method !== "GET" && req.method !== "HEAD") return next();
    res.vary("Authorization");
    res.vary("Accept-Language");
    if (req.headers.authorization || maxAge === 0) res.setHeader("Cache-Control", "private, no-cache");
    else res.setHeader("Cache-Control", `public, max-age=${maxAge}, stale-while-revalidate=${stale}`);
    // Errors must never be cached
    const json = res.json.bind(res);
    res.json = (body: unknown) => {
      if (res.statusCode >= 400) res.setHeader("Cache-Control", "no-store");
      return json(body);
    };
    const send = res.send.bind(res);
    res.send = (body?: any) => {
      if (res.statusCode >= 400) res.setHeader("Cache-Control", "no-store");
      return send(body);
    };
    next();
  };
}

/** The public GET routes, mounted before the routers that serve them. */
export const publicCacheRoutes = Router();
const api = publicCache();
for (const path of [
  "/api/v1/stores",
  "/api/v1/stores/:id(\\d+)",
  "/api/v1/stores/:id(\\d+)/products",
  "/api/v1/stores/:id(\\d+)/drops",
  "/api/v1/products/search",
  "/api/v1/products/:id(\\d+)",
  "/api/v1/drops/feed",
  "/api/v1/drops/ranking",
  "/api/v1/drops/:id(\\d+)",
]) publicCacheRoutes.get(path, api);
// Pages people open from links: a little longer
const pages = publicCache(Math.max(scale.publicCacheSeconds, 60), Math.max(scale.publicStaleSeconds, 600));
for (const path of ["/d/:id", "/s/:storeId", "/r/:code"]) publicCacheRoutes.get(path, pages);
// Legal texts change rarely (every change is a new version)
publicCacheRoutes.get("/legal/*", publicCache(300, 3600));
publicCacheRoutes.get("/.well-known/assetlinks.json", publicCache(3600, 86_400));
