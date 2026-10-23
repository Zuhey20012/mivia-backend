import { fold } from "./matcher";

/**
 * Claims checker (spec §2.14, AB §5): generic environmental claims are banned since 27 Sept 2026 (Directive (EU)
 * 2024/825, Finnish Act 573/2026) unless backed by recognised excellent environmental performance. The words below in a
 * product's name or description give a warning on drafts and block publishing (422).
 *
 * Words that also have an everyday, non-environmental meaning are only warnings, never blocks: "green" / "vihreä" (a
 * colour), "natural" / "luonnollinen" (a makeup finish), "kestävä" (durable), "responsible" (responsible person),
 * "conscious".
 */

type Rule = { term: string; re: RegExp; block: boolean };

// Finnish stems match inside words (ympäristöystävällistä, vastuullisesti); English words at word boundaries.
const fiStem = (stem: string) => new RegExp(`${fold(stem)}`, "u");
const enWord = (w: string) => new RegExp(`(?<![\\p{L}\\p{N}])${fold(w).replace(/[- ]/g, "[- ]?")}(?![\\p{L}\\p{N}])`, "u");
const enPrefix = (w: string) => new RegExp(`(?<![\\p{L}\\p{N}])${fold(w)}`, "u");

const RULES: Rule[] = [
  // Finnish (blocking)
  { term: "ympäristöystävällinen", re: fiStem("ymparistoystavalli"), block: true },
  { term: "luontoystävällinen", re: fiStem("luontoystavalli"), block: true },
  { term: "ilmastoystävällinen", re: fiStem("ilmastoystavalli"), block: true },
  { term: "ekoystävällinen", re: fiStem("ekoystavalli"), block: true },
  { term: "ekologinen", re: fiStem("ekologi"), block: true },
  { term: "eko-", re: /(?<![\p{L}\p{N}])eko(?:-|(?![\p{L}\p{N}]))/u, block: true },
  { term: "vastuullinen", re: fiStem("vastuulli"), block: true },
  { term: "kestävästi", re: fiStem("kestavasti"), block: true },
  { term: "kestävä kehitys", re: fiStem("kestava kehity"), block: true },
  { term: "hiilineutraali", re: fiStem("hiilineutraal"), block: true },
  { term: "ilmastoneutraali", re: fiStem("ilmastoneutraal"), block: true },
  { term: "hiilipositiivinen", re: fiStem("hiilipositiivi"), block: true },
  { term: "biohajoava", re: fiStem("biohajoa"), block: true },
  { term: "kompostoituva", re: fiStem("kompostoitu"), block: true },
  // English (blocking)
  { term: "eco", re: /(?<![\p{L}\p{N}])eco(?:-|(?![\p{L}\p{N}]))/u, block: true },
  { term: "eco-friendly", re: /(?<![\p{L}\p{N}])eco[- ]?friendly/u, block: true },
  { term: "ecological", re: enPrefix("ecologic"), block: true },
  { term: "environmentally friendly", re: /environment(?:ally)?[- ]?friendly/u, block: true },
  { term: "planet-friendly", re: /planet[- ]?friendly/u, block: true },
  { term: "climate friendly", re: /climate[- ]?friendly/u, block: true },
  { term: "climate neutral", re: /climate[- ]?neutral/u, block: true },
  { term: "carbon neutral", re: /carbon[- ]?(?:neutral|negative|positive)/u, block: true },
  { term: "sustainable", re: enPrefix("sustainab"), block: true },
  { term: "biodegradable", re: enPrefix("biodegradab"), block: true },
  { term: "compostable", re: enPrefix("compostab"), block: true },
  // Ambiguous: warnings only
  { term: "green", re: enWord("green"), block: false },
  { term: "vihreä", re: fiStem("vihrea"), block: false },
  { term: "kestävä", re: /(?<![\p{L}\p{N}])kestava(?![\p{L}\p{N}])/u, block: false },
  { term: "responsible", re: /(?<![\p{L}\p{N}])responsibl[ey](?![- ]person)(?![\p{L}])/u, block: false },
  { term: "conscious", re: enWord("conscious"), block: false },
  { term: "natural", re: enWord("natural"), block: false },
  { term: "luonnollinen", re: fiStem("luonnolli"), block: false },
];

export type ClaimHit = {
  field: "name" | "description" | "tags";
  term: string;
  blocking: boolean;
  message: { en: string; fi: string };
};

function messageFor(term: string, blocking: boolean) {
  return blocking
    ? {
      en: `"${term}" is a generic environmental claim, banned without a recognised ecolabel. State a specific fact (e.g. "60 % recycled polyester, GRS") or add a verified certificate.`,
      fi: `"${term}" on yleinen ympäristöväittämä, joka on kielletty ilman tunnustettua ympäristömerkkiä. Kerro tarkka tieto (esim. "60 % kierrätettyä polyesteriä, GRS") tai lisää todennettu sertifikaatti.`,
    }
    : {
      en: `Check "${term}": if it describes the environment or ethics, replace it with a specific, verifiable fact. As a colour, finish or plain description it is fine.`,
      fi: `Tarkista "${term}": jos se kuvaa ympäristöä tai vastuullisuutta, korvaa se tarkalla, todennettavalla tiedolla. Värinä, viimeistelynä tai tavallisena kuvauksena se on sallittu.`,
    };
}

export function checkClaims(fields: { name?: string | null; description?: string | null; tags?: string[] | null }): ClaimHit[] {
  const hits: ClaimHit[] = [];
  const scan = (field: ClaimHit["field"], text: string | null | undefined) => {
    if (!text) return;
    const t = fold(text);
    for (const r of RULES) {
      if (r.re.test(t) && !hits.some((h) => h.field === field && h.term === r.term)) {
        hits.push({ field, term: r.term, blocking: r.block, message: messageFor(r.term, r.block) });
      }
    }
  };
  scan("name", fields.name);
  scan("description", fields.description);
  for (const tag of fields.tags ?? []) scan("tags", tag);
  // A more specific term already covers the generic one ("eco-friendly" also matches "eco")
  return hits.filter((h) => !(h.term === "eco" && hits.some((o) => o.field === h.field && o.term !== "eco" && o.term.startsWith("eco"))));
}

/** Tags that are generic green words are never stored (imports and the editor). */
export function isGreenTag(tag: string) {
  return checkClaims({ name: tag }).some((h) => h.blocking);
}
