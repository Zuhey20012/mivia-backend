import dns from "dns/promises";
import net from "net";
import { env } from "../../config/env";
import { ApiError } from "../../lib/errors";

/**
 * Outbound requests to a shop's public feed (SSRF guard): plain https hostnames only (no IPs, no
 * localhost or internal names, no ports, no credentials), every resolved address must be public,
 * redirects are followed by hand and checked the same way, with timeouts and a size cap.
 * IMPORT_ALLOW_HOSTS (test only, ignored in production) lets the e2e suite reach its local mock.
 */

const HOSTNAME = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const INTERNAL_SUFFIXES = [".localhost", ".local", ".internal", ".lan", ".home.arpa", ".arpa", ".test", ".invalid", ".example", ".onion"];

const PRIVATE = new net.BlockList();
for (const [addr, prefix] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12],
  ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
] as [string, number][]) PRIVATE.addSubnet(addr, prefix, "ipv4");
for (const [addr, prefix] of [["::", 128], ["::1", 128], ["fc00::", 7], ["fe80::", 10], ["ff00::", 8], ["64:ff9b::", 96], ["2001:db8::", 32]] as [string, number][]) {
  PRIVATE.addSubnet(addr, prefix, "ipv6");
}

function isPrivateAddress(address: string) {
  const v = net.isIP(address);
  if (v === 4) return PRIVATE.check(address, "ipv4");
  if (v === 6) {
    const mapped = address.toLowerCase().match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return PRIVATE.check(mapped[1], "ipv4");
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

/** Every address the name resolves to must be public (no internal network, no cloud metadata). */
export async function assertPublicHost(u: URL) {
  if (allowListed(u)) return;
  let addresses: { address: string }[];
  try {
    addresses = await dns.lookup(u.hostname, { all: true, verbatim: true });
  } catch {
    throw new ApiError("That shop address could not be found", 400);
  }
  if (!addresses.length || addresses.some((a) => isPrivateAddress(a.address))) {
    throw new ApiError("That shop address is not a public website", 400);
  }
}

/** GET a JSON document from a public site: manual redirects (max 3, each checked), timeout, size cap. */
export async function fetchPublicJson(start: URL, opts: { maxBytes: number; timeoutMs: number }): Promise<unknown> {
  let url = start;
  for (let hop = 0; hop <= 3; hop++) {
    checkUrlShape(url);
    await assertPublicHost(url);
    const res = await fetch(url, {
      redirect: "manual",
      headers: { Accept: "application/json", "User-Agent": "MalvoyaCatalogueImport/1.0" },
      signal: AbortSignal.timeout(opts.timeoutMs),
    });
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get("location");
      await res.body?.cancel().catch(() => {});
      if (!location) throw new ApiError("The shop sent an invalid redirect", 502);
      url = new URL(location, url);
      continue;
    }
    if (!res.ok) {
      await res.body?.cancel().catch(() => {});
      throw new ApiError(res.status === 404 ? "This shop has no public product feed (products.json)" : `The shop answered with an error (${res.status})`, 502);
    }
    const declared = Number(res.headers.get("content-length"));
    if (declared > opts.maxBytes) throw new ApiError("The product feed is too large", 502);
    const reader = res.body?.getReader();
    if (!reader) throw new ApiError("The shop sent an empty answer", 502);
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > opts.maxBytes) {
        await reader.cancel().catch(() => {});
        throw new ApiError("The product feed is too large", 502);
      }
      chunks.push(value);
    }
    try {
      return JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      throw new ApiError("The shop's product feed is not valid JSON", 502);
    }
  }
  throw new ApiError("The shop redirected too many times", 502);
}
