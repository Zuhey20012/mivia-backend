import { z } from "zod";

/**
 * Copyright and trademark notices (DSA Art. 16(2); since 2.16.0). Reports of products, drops and drop comments with the
 * reason copyright / trademark must carry what Art. 16(2) asks of a notice: the notifier's name and email, the work or
 * mark concerned (with why it is infringed: `work` and the report's details), the exact location, and a statement that
 * the notice is accurate and complete and made in good faith. How rights holders report, the counter-notice route and
 * the repeat-infringer policy: legal/ip_notice.md (/legal/ip-notice). The US DMCA does not apply to Malvoya (a Finnish
 * service for Finland); the EU DSA notice-and-action rules do.
 */
export const IP_REASONS = ["copyright", "trademark", "COPYRIGHT", "TRADEMARK"] as const;

export const isIpReason = (reason: string) => (IP_REASONS as readonly string[]).includes(reason);

export const ipNoticeSchema = z.object({
  name: z.string().trim().min(2).max(120),
  email: z.string().trim().email().max(200),
  // The work or mark concerned, e.g. "My photograph 'Kallio at dusk' (2025)" or "EU trade mark 018123456 MALVA"
  work: z.string().trim().min(5).max(500),
  // Where it is: the link or a description of where on the page (the reported item is already known)
  location: z.string().trim().min(3).max(500),
  // Optional: whether the notifier is the rights holder or acts for one
  onBehalfOf: z.string().trim().max(200).optional(),
  goodFaith: z.literal(true),
});

export type IpNotice = z.infer<typeof ipNoticeSchema>;

export const IP_NOTICE_REQUIRED = {
  en: "For a copyright or trademark report, give your name, email, the work or mark concerned, where it is used, and tick the good-faith statement.",
  fi: "Tekijänoikeus- tai tavaramerkki-ilmoitukseen tarvitaan nimesi, sähköpostiosoitteesi, kyseinen teos tai tavaramerkki, sen käyttöpaikka sekä vilpittömän mielen vakuutus.",
};

/**
 * Checks the notice of an IP report. Returns the stored form (with the time of the statement) or an error message
 * in both languages; other reasons need no notice and store none.
 */
export function readIpNotice(reason: string, raw: unknown): { ok: true; value: (IpNotice & { at: string }) | null } | { ok: false; error: string } {
  if (!isIpReason(reason)) return { ok: true, value: null };
  const parsed = ipNoticeSchema.safeParse(raw);
  if (!parsed.success) return { ok: false, error: `${IP_NOTICE_REQUIRED.en} / ${IP_NOTICE_REQUIRED.fi}` };
  return { ok: true, value: { ...parsed.data, at: new Date().toISOString() } };
}
