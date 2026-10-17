import { prisma } from "./prisma";

/**
 * Language of server-sent messages (push notifications, emails, SMS). Every text is written in both
 * languages next to where it is used, as `t(en, fi)`, and picked per recipient: User.locale ("fi" | "en"),
 * which the apps set through Accept-Language (stored only when it changes) or PATCH /me. A recipient who never
 * told us gets English; "fi" only when the app said fi.
 */
export type Locale = "fi" | "en";
export type Text = string | { en: string; fi: string };

export const t = (en: string, fi: string) => ({ en, fi });

/** The text in the given language (plain strings are the same in both). */
export function pick(text: Text, locale: Locale): string {
  return typeof text === "string" ? text : locale === "fi" ? text.fi : text.en;
}

/** A stored or requested locale → "fi" or "en" (anything but fi is English). */
export function asLocale(value: string | null | undefined): Locale {
  return value === "fi" ? "fi" : "en";
}

/** The first language of an Accept-Language header: "fi" for Finnish, "en" for anything else, null without one. */
export function localeFromHeader(header: string | string[] | undefined): Locale | null {
  const raw = Array.isArray(header) ? header[0] : header;
  if (!raw || !raw.trim()) return null;
  const first = raw.split(",")[0].split(";")[0].trim().toLowerCase();
  if (!first || first === "*") return null;
  return first === "fi" || first.startsWith("fi-") ? "fi" : "en";
}

export async function localeOfUser(userId: number): Promise<Locale> {
  const u = await prisma.user.findUnique({ where: { id: userId }, select: { locale: true } }).catch(() => null);
  return asLocale(u?.locale);
}

/** Emails are sent to addresses; this finds the account's language for one (English when unknown). */
export async function localeOfEmail(email: string | null | undefined): Promise<Locale> {
  if (!email) return "en";
  const u = await prisma.user.findFirst({ where: { email: { equals: email, mode: "insensitive" } }, select: { locale: true } }).catch(() => null);
  return asLocale(u?.locale);
}

/** Money in the reader's format: 12,90 € (fi) or 12.90 € (en). */
export function euro(cents: number, locale: Locale) {
  const s = (cents / 100).toFixed(2);
  return `${locale === "fi" ? s.replace(".", ",") : s} €`;
}

/** Money for a two-language text: { en: "12.90 €", fi: "12,90 €" }. */
export const euros = (cents: number) => ({ en: euro(cents, "en"), fi: euro(cents, "fi") });

/** Several texts joined with spaces, per language. */
export function joinText(...parts: (Text | null | undefined | false)[]): { en: string; fi: string } {
  const kept = parts.filter((p): p is Text => !!p);
  return { en: kept.map((p) => pick(p, "en")).join(" "), fi: kept.map((p) => pick(p, "fi")).join(" ") };
}

/** "Tonight 17:00–19:00" → "tonight 17:00–19:00" (for use inside a sentence), per language. */
export function lowerFirst(text: { en: string; fi: string }) {
  const lc = (s: string) => (s ? s[0].toLowerCase() + s.slice(1) : s);
  return { en: lc(text.en), fi: lc(text.fi) };
}
