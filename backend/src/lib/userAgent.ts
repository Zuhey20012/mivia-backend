/**
 * A short, readable device name from a User-Agent (Settings → Signed-in devices, new sign-in emails). Only the family,
 * never the full string or the IP address.
 */
export function deviceName(ua: string | null | undefined): string {
  if (!ua) return "Unknown device";
  const s = ua.toLowerCase();
  // The Flutter apps send "Dart/3.x (dart:io)" plus, from 2.16, "MalvoyaCustomer/1.9 (Android 14)" style tokens
  const app = /malvoya[ _-]?(customer|store|vendor|courier)/i.exec(ua);
  const os = s.includes("android") ? "Android" : /iphone|ipad|ios/.test(s) ? "iOS" : s.includes("windows") ? "Windows"
    : s.includes("mac os") || s.includes("macintosh") ? "macOS" : s.includes("linux") ? "Linux" : null;
  if (app) {
    const name = app[1].toLowerCase() === "vendor" ? "Store" : app[1][0].toUpperCase() + app[1].slice(1).toLowerCase();
    return `Malvoya ${name} app${os ? ` (${os})` : ""}`;
  }
  if (s.startsWith("dart/") || s.includes("dart:io")) return `Malvoya app${os ? ` (${os})` : ""}`;
  const browser = s.includes("edg/") ? "Edge" : s.includes("firefox/") ? "Firefox" : s.includes("chrome/") ? "Chrome"
    : s.includes("safari/") ? "Safari" : null;
  if (browser) return `${browser}${os ? ` on ${os}` : ""}`;
  if (s.startsWith("node") || s.includes("undici")) return "Script or test client";
  return os ? `Device (${os})` : "Unknown device";
}
