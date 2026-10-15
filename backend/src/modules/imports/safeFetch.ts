import { promises as dnsPromises, LookupAddress } from "dns";
import http from "http";
import https from "https";
import net from "net";
import { env } from "../../config/env";
import { ApiError } from "../../lib/errors";

/**
 * Outbound requests to a shop's public feed (SSRF guard): plain https hostnames only (no IPs, no
 * localhost or internal names, no ports, no credentials), every resolved address must be public,
 * redirects are followed by hand and checked the same way, with timeouts and a size cap.
 * The address check runs again inside the connection itself (the socket's `lookup`), so a name that
 * resolves differently the second time (DNS rebinding) can never reach an internal address.
 * Names are resolved with c-ares (dns Resolver) with a short timeout instead of the blocking libuv pool.
 * IMPORT_ALLOW_HOSTS (test only, ignored in production) lets the e2e suite reach its local mock.
 */

const HOSTNAME = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const INTERNAL_SUFFIXES = [".localhost", ".local", ".internal", ".lan", ".home.arpa", ".arpa", ".test", ".invalid", ".example", ".onion"];
const DNS_TIMEOUT_MS = 3000;

const PRIVATE = new net.BlockList();
for (const [addr, prefix] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12],
  ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
] as [string, number][]) PRIVATE.addSubnet(addr, prefix, "ipv4");
for (const [addr, prefix] of [
  ["::", 96], // unspecified, loopback and IPv4-compatible addresses
  ["fc00::", 7], ["fe80::", 10], ["ff00::", 8],
  ["64:ff9b::", 96], ["64:ff9b:1::", 48], // NAT64
  ["2002::", 16], // 6to4 (embeds any IPv4 address)
  ["2001:db8::", 32],
] as [string, number][]) {
  PRIVATE.addSubnet(addr, prefix, "ipv6");
}

export function isPrivateAddress(address: string) {
  const v = net.isIP(address);
  if (v === 4) return PRIVATE.check(address, "ipv4");
  if (v === 6) {
    const mapped = address.toLowerCase().match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return PRIVATE.check(mapped[1], "ipv4");
    if (/^::ffff:/i.test(address)) return true; // IPv4-mapped in hex form
    return PRIVATE.check(address, "ipv6");
  }
  return true;
}

function allowListed(u: URL) {
  return env.importAllowHosts.includes(`${u.hostname}:${u.port || (u.protocol === "https:" ? "443" : "80")}`.toLowerCase());
}

/** Checks the form of an address; throws a user-readable 400. */
export function checkUrlShape(u: URL) {
  if (u.username || u.password) throw new ApiError("Enter the shop address without a user name or password", 400);
  if (allowListed(u)) return;
  if (u.protocol !== "https:") throw new ApiError("The shop address must start with https://", 400);
  const host = u.hostname.toLowerCase();
  if (u.port) throw new ApiError("Enter the shop address without a port number", 400);
  if (net.isIP(host.replace(/^\[|\]$/g, "")) || !HOSTNAME.test(host) || INTERNAL_SUFFIXES.some((s) => host.endsWith(s))) {
    throw new ApiError("Enter your shop's public web address, e.g. https://myshop.com", 400);
  }
}

/** "myshop.com", "https://myshop.com/collections/x" → https://myshop.com (origin only). */
export function parseShopUrl(input: string): URL {
  const raw = input.trim();
  let u: URL;
  try {
    u = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `https://${raw}`);
  } catch {
    throw new ApiError("That is not a valid web address", 400);
  }
  checkUrlShape(u);
  return new URL(u.origin);
}

/** All A and AAAA answers for a name, with a short timeout. Empty when the name does not exist. */
async function resolveAll(hostname: string): Promise<LookupAddress[]> {
  const resolver = new dnsPromises.Resolver({ timeout: DNS_TIMEOUT_MS, tries: 2 });
  const [v4, v6] = await Promise.allSettled([resolver.resolve4(hostname), resolver.resolve6(hostname)]);
  const out: LookupAddress[] = [];
  if (v4.status === "fulfilled") out.push(...v4.value.map((address) => ({ address, family: 4 })));
  if (v6.status === "fulfilled") out.push(...v6.value.map((address) => ({ address, family: 6 })));
  return out;
}

/** Every address the name resolves to must be public (no internal network, no cloud metadata). */
export async function assertPublicHost(u: URL) {
  if (allowListed(u)) return;
  const addresses = await resolveAll(u.hostname).catch(() => [] as LookupAddress[]);
  if (!addresses.length) throw new ApiError("That shop address could not be found", 400);
  if (addresses.some((a) => isPrivateAddress(a.address))) throw new ApiError("That shop address is not a public website", 400);
}

/** The socket's own lookup: resolves again and refuses private answers at connection time. */
function guardedLookup(hostname: string, options: { all?: boolean }, callback: (...args: any[]) => void) {
  resolveAll(hostname).then((addresses) => {
    if (!addresses.length) return callback(Object.assign(new Error(`getaddrinfo ENOTFOUND ${hostname}`), { code: "ENOTFOUND" }));
    if (addresses.some((a) => isPrivateAddress(a.address))) {
      return callback(Object.assign(new Error("Refusing to connect to a non-public address"), { code: "EPRIVATE" }));
    }
    if (options?.all) return callback(null, addresses);
    callback(null, addresses[0].address, addresses[0].family);
  }, (err) => callback(err));
}

type Answer = { status: number; location: string | null; body: Buffer | null };

/** One GET without following redirects. Public hosts go through the guarded lookup. */
type FetchOpts = {
  maxBytes: number; timeoutMs: number;
  /** Sent only to the starting origin (e.g. WooCommerce API keys as Basic auth); a redirect elsewhere is refused. */
  authorization?: string;
  /** A user-readable message for an error status (else the generic one). */
  errorFor?: (status: number) => string | null;
};

function getOnce(url: URL, opts: FetchOpts): Promise<Answer> {
  return new Promise((resolve, reject) => {
    const client = url.protocol === "https:" ? https : http;
    const req = client.request(url, {
      method: "GET",
      headers: {
        Accept: "application/json", "User-Agent": "MalvoyaCatalogueImport/1.0",
        ...(opts.authorization ? { Authorization: opts.authorization } : {}),
      },
      ...(allowListed(url) ? {} : { lookup: guardedLookup as any }),
      timeout: opts.timeoutMs,
    }, (res) => {
      const status = res.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        res.resume();
        return resolve({ status, location: res.headers.location ?? null, body: null });
      }
      if (status < 200 || status >= 300) {
        res.resume();
        return resolve({ status, location: null, body: null });
      }
      const declared = Number(res.headers["content-length"]);
      if (declared > opts.maxBytes) {
        res.destroy();
        return reject(new ApiError("The product feed is too large", 502));
      }
      const chunks: Buffer[] = [];
      let size = 0;
      res.on("data", (c: Buffer) => {
        size += c.length;
        if (size > opts.maxBytes) {
          res.destroy();
          reject(new ApiError("The product feed is too large", 502));
          return;
        }
        chunks.push(c);
      });
      res.on("end", () => resolve({ status, location: null, body: Buffer.concat(chunks) }));
      res.on("error", reject);
    });
    // Overall deadline as well as the idle timeout
    const deadline = setTimeout(() => req.destroy(new Error("timeout")), opts.timeoutMs);
    req.on("close", () => clearTimeout(deadline));
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", (e: any) => reject(e?.code === "EPRIVATE"
      ? new ApiError("That shop address is not a public website", 400)
      : e instanceof ApiError ? e : new ApiError("The shop could not be reached", 502)));
    req.end();
  });
}

/** GET a JSON document from a public site: manual redirects (max 3, each checked), timeout, size cap. */
export async function fetchPublicJson(start: URL, opts: FetchOpts): Promise<unknown> {
  let url = start;
  for (let hop = 0; hop <= 3; hop++) {
    checkUrlShape(url);
    await assertPublicHost(url);
    const res = await getOnce(url, opts);
    if (res.status >= 300 && res.status < 400) {
      if (!res.location) throw new ApiError("The shop sent an invalid redirect", 502);
      const next = new URL(res.location, url);
      // Credentials never follow a redirect to another site
      if (opts.authorization && next.origin !== start.origin) throw new ApiError("The shop redirected to another site; enter its final address", 502);
      url = next;
      continue;
    }
    if (!res.body) {
      const custom = opts.errorFor?.(res.status);
      if (custom) throw new ApiError(custom, 502);
      throw new ApiError(res.status === 404 ? "This shop has no public product feed (products.json)" : `The shop answered with an error (${res.status})`, 502);
    }
    try {
      return JSON.parse(res.body.toString("utf8"));
    } catch {
      throw new ApiError("The shop's product feed is not valid JSON", 502);
    }
  }
  throw new ApiError("The shop redirected too many times", 502);
}
