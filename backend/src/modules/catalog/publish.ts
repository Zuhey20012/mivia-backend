import { FieldIssue, compositionProblems } from "./attributes";
import { checkClaims, ClaimHit } from "./claims";
import { HOLD_REASONS, Template, isCosmetic } from "./taxonomy";

/**
 * Publishing rules: before a product can be visible, the legally required information of its template must be there
 * (docs/compliance/apparel-beauty.md; spec §2). Drafts may be incomplete. Each problem is a field-level issue with an
 * English and a Finnish message; the API answers 422 { code: "PUBLISH_REQUIREMENTS", fields: [...] }.
 *
 * Seller type matters where the law does: the GPSR listing information (Art. 19) and the textile/footwear label facts
 * are duties of traders, so a private person selling their own second-hand things may say "label missing"; cosmetics,
 * skincare, haircare and fragrance are business-only at launch (AB §3.7).
 */

const l = (en: string, fi: string) => ({ en, fi });

export const EU_EEA = new Set([
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
  "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO",
]);
export const inEu = (country: string | null | undefined) => !!country && EU_EEA.has(country.toUpperCase());

/** Hygiene seal only for genuinely sealed goods (AB §6, CJEU C-681/17): cosmetics, fragrance, sealed piercing jewellery and earrings. */
export function hygieneSealAllowed(slug: string | null, template: Template | null) {
  return isCosmetic(template) || slug === "jewellery-piercing" || slug === "jewellery-earrings";
}

export type PublishCandidate = {
  name: string;
  description: string | null;
  tags: string[];
  categorySlug: string | null;
  template: Template | null;
  audience: string;
  condition: string;
  isSecondHand: boolean;
  attributes: Record<string, any>;
  contentAmount: number | null;
  contentUnit: string | null;
  variants: { contentAmount: number | null; contentUnit: string | null; colourFamily: string | null }[];
  manufacturer: { countryCode: string } | null;
  responsiblePerson: { countryCode: string } | null;
  productModel: string | null;
  warningsFi: string | null;
  warningsSv: string | null;
  noWarnings: boolean;
  importHold: string | null;
  /** The GTIN or brand + model is in an active recall */
  recalled: boolean;
};
export type PublishStore = { sellerType: string; safetyPledgeAt: Date | null };

const has = (s: unknown) => typeof s === "string" && s.trim().length > 0;
const bothLangs = (v: any) => has(v?.fi) && has(v?.sv);

export type PublishCheck = { ready: boolean; missing: FieldIssue[]; warnings: FieldIssue[] };

export function publishCheck(p: PublishCandidate, store: PublishStore): PublishCheck {
  const missing: FieldIssue[] = [];
  const warnings: FieldIssue[] = [];
  const need = (field: string, message: { en: string; fi: string }, code = "required") => missing.push({ field, code, message });
  const warn = (field: string, message: { en: string; fi: string }, code = "recommended") => warnings.push({ field, code, message });
  const business = store.sellerType !== "PRIVATE";
  const a = p.attributes ?? {};
  const t = p.template;

  if (!store.safetyPledgeAt) {
    need("safetyPledge", l(
      "Confirm once that you only offer products that comply with EU law (product safety pledge) before publishing.",
      "Vahvista kerran, että tarjoat vain EU-lainsäädännön mukaisia tuotteita (tuoteturvallisuussitoumus), ennen julkaisua.",
    ));
  }
  if (p.importHold) {
    const r = HOLD_REASONS[p.importHold] ?? l("this kind of product is not sold on Malvoya.", "tällaisia tuotteita ei myydä Malvoyassa.");
    need("categorySlug", l(`On hold: ${r.en} If this is wrong, pick the right category.`, `Pidossa: ${r.fi} Jos tämä on virhe, valitse oikea kategoria.`), "held");
  }
  if (!p.categorySlug || !t) {
    need("categorySlug", l("Pick a category for the product.", "Valitse tuotteelle kategoria."));
  }
  if (p.recalled) {
    need("gtin", l("This product is part of a product safety recall and cannot be listed.", "Tuote kuuluu tuoteturvallisuuteen liittyvään takaisinvetoon, eikä sitä voi myydä."), "recalled");
  }

  const claims: ClaimHit[] = checkClaims({ name: p.name, description: p.description });
  for (const c of claims) (c.blocking ? need : warn)(c.field, c.message, c.blocking ? "generic_green_claim" : "check_claim");

  if (isCosmetic(t) && !business) {
    need("categorySlug", l(
      "Cosmetics, skincare, haircare and fragrance can only be sold by business sellers on Malvoya.",
      "Kosmetiikkaa, ihon- ja hiustenhoitotuotteita sekä tuoksuja voivat myydä Malvoyassa vain yritysmyyjät.",
    ), "business_only");
  }

  // GPSR Art. 19 (business sellers): manufacturer, EU responsible person when outside the EU, type, warnings FI + SV
  if (business && t) {
    if (!p.manufacturer) {
      need("manufacturerId", l(
        "Add the manufacturer's name and address. EU product safety law requires them online.",
        "Lisää valmistajan nimi ja osoite. EU:n tuoteturvallisuusasetus vaatii ne verkkokaupassa.",
      ));
    } else if (!inEu(p.manufacturer.countryCode) && !p.responsiblePerson) {
      need("responsiblePersonId", l(
        "The manufacturer is outside the EU: add the EU responsible person.",
        "Valmistaja on EU:n ulkopuolella: lisää vastuuhenkilö EU:ssa.",
      ));
    }
    if (!has(p.productModel)) {
      need("productModel", l("Add the product's model or type as on the label.", "Lisää tuotteen malli tai tyyppi pakkausmerkinnän mukaan."));
    }
    const cosmeticWarnings = isCosmetic(t) && (bothLangs(a.precautions) || a.noPrecautions === true);
    if (!p.noWarnings && !cosmeticWarnings && !(has(p.warningsFi) && has(p.warningsSv))) {
      need("warnings", has(p.warningsFi) || has(p.warningsSv)
        ? l("Warnings are needed in Finnish and Swedish.", "Varoitukset tarvitaan suomeksi ja ruotsiksi.")
        : l("Add the warnings and safety information in Finnish and Swedish, or confirm the label has none.", "Lisää varoitukset ja turvallisuustiedot suomeksi ja ruotsiksi tai vahvista, ettei pakkauksessa ole niitä."));
    }
  }

  const privateSecondHand = !business && p.isSecondHand;
  if (t === "APPAREL" || t === "APPAREL_ACCESSORY" || ((t === "BAG" || t === "ACCESSORY") && Array.isArray(a.mainMaterial) && a.mainMaterial.length === 1 && a.mainMaterial[0] === "textile")) {
    const exempt = (privateSecondHand && a.fibreCompositionUnknown === true) || (t !== "APPAREL" && a.textileUnder80 === true);
    if (!exempt) {
      if (!Array.isArray(a.fibreComposition) || !a.fibreComposition.length) {
        need("attributes.fibreComposition", privateSecondHand
          ? l("Add the material from the label, or say the label is missing.", "Lisää materiaali lapusta tai kerro, että lappu puuttuu.")
          : l("Add the fibre composition with percentages (EU textile regulation).", "Lisää kuitukoostumus prosentteineen (EU:n tekstiiliasetus)."));
      } else {
        missing.push(...compositionProblems(a.fibreComposition));
      }
    }
  }
  if (p.audience === "KIDS" && (t === "APPAREL" || t === "APPAREL_ACCESSORY")) {
    if (!a.cordsDrawstrings) {
      need("attributes.cordsDrawstrings", l("Children's clothes: say whether there are cords or drawstrings.", "Lastenvaatteet: kerro, onko vaatteessa naruja tai kiristysnyörejä."));
    } else if (a.cordsDrawstrings === "present_hood_neck") {
      need("attributes.cordsDrawstrings", l(
        "Children's clothes for under-7s can't have cords in the hood or neck area (EN 14682).",
        "Lasten vaatteessa ei saa olla nyörejä hupussa tai kaulan alueella (alle 7 v, EN 14682).",
      ), "not_allowed");
    }
    if (a.costumeIsToy === true) need("attributes.costumeIsToy", l("Fancy-dress costumes are toys and can't be sold on Malvoya yet.", "Naamiaisasut ovat leluja, eikä niitä voi vielä myydä Malvoyassa."), "not_allowed");
  }
  if (t === "FOOTWEAR" && !privateSecondHand) {
    for (const [key, en, fi] of [
      ["materialUpper", "upper", "päällisen"], ["materialLiningSock", "lining and insole", "vuorin ja sisäpohjan"], ["materialOuterSole", "outer sole", "ulkopohjan"],
    ] as const) {
      if (!Array.isArray(a[key]) || !a[key].length) need(`attributes.${key}`, l(`Add the material of the ${en} (footwear labelling).`, `Lisää ${fi} materiaali (jalkineiden merkinnät).`));
    }
  }
  if (t === "EYEWEAR" && business) {
    if (typeof a.uvFilterCategory !== "number") need("attributes.uvFilterCategory", l("Add the UV filter category (0–4) from the label.", "Lisää UV-suojaluokka (0–4) merkinnöistä."));
    if (a.ceMarked !== true) need("attributes.ceMarked", l("Sunglasses must be CE marked.", "Aurinkolasien on oltava CE-merkityt."));
  }
  if (t === "WATCH" && a.movement === "smart") {
    need("attributes.movement", l("Smart watches are radio equipment and can't be sold on Malvoya yet.", "Älykellot ovat radiolaitteita, eikä niitä voi vielä myydä Malvoyassa."), "not_allowed");
  }
  if (t === "JEWELLERY" && business && p.condition === "NEW") {
    if (!a.nickelBasis || a.nickelBasis === "not_known") {
      need("attributes.nickelBasis", l(
        "Say how the nickel release is known to be within the limit (test report, supplier declaration or nickel-free material).",
        "Kerro, miten nikkelin vapautumisen tiedetään olevan rajan alla (testiraportti, toimittajan vakuutus tai nikkelitön materiaali).",
      ));
    }
    const precious = ["gold", "white_gold", "rose_gold", "silver_925", "sterling_silver", "platinum", "palladium"];
    if (!precious.includes(a.metal) && !a.leadCadmiumBasis) {
      need("attributes.leadCadmiumBasis", l("Say how lead and cadmium are known to be within the limits.", "Kerro, miten lyijyn ja kadmiumin tiedetään olevan rajojen alla."));
    }
  }
  if (isCosmetic(t)) {
    const contentOk = (p.contentAmount && p.contentUnit) || (p.variants.length > 0 && p.variants.every((v) => v.contentAmount && v.contentUnit));
    if (!contentOk) need("contentAmount", l("Enter the content (ml or g) so the price per litre or kg can be shown.", "Anna sisältö (ml tai g), jotta litra- tai kilohinta voidaan näyttää."));
    if (!a.durabilityType) need("attributes.durabilityType", l("Add the shelf life: best-before date or period after opening.", "Lisää säilyvyys: parasta ennen -päiväys tai käyttöaika avaamisen jälkeen."));
    if (a.durabilityType === "pao" && !a.paoMonths) need("attributes.paoMonths", l("Add the period after opening in months.", "Lisää käyttöaika avaamisen jälkeen kuukausina."));
    if (a.durabilityType === "best_before") {
      if (!a.bestBefore) need("attributes.bestBefore", l("Add the best-before month.", "Lisää parasta ennen -kuukausi."));
      else if (String(a.bestBefore) < new Date().toISOString().slice(0, 7)) need("attributes.bestBefore", l("The best-before date has passed.", "Parasta ennen -päiväys on mennyt."), "expired");
    }
    if (!bothLangs(a.function)) need("attributes.function", l("Say what the product is for, in Finnish and Swedish.", "Kerro tuotteen käyttötarkoitus suomeksi ja ruotsiksi."));
    if (!bothLangs(a.precautions) && a.noPrecautions !== true) need("attributes.precautions", l("Add the precautions in Finnish and Swedish, or confirm the label has none.", "Lisää varotoimet suomeksi ja ruotsiksi tai vahvista, ettei pakkauksessa ole niitä."));
    if (!has(a.ingredientsInci) || String(a.ingredientsInci).trim().length < 3) need("attributes.ingredientsInci", l("Add the ingredient list (INCI) as printed on the pack.", "Lisää ainesosaluettelo (INCI) pakkauksen mukaan."));
    if (a.sealedUnused !== true) need("attributes.sealedUnused", l("Only sealed, unused cosmetics can be sold: confirm it.", "Vain avaamatonta ja käyttämätöntä kosmetiikkaa voi myydä: vahvista se."));
    if (a.isTesterOrSample === true) need("attributes.isTesterOrSample", l("Testers and samples are not for sale.", "Testereitä ja näytteitä ei saa myydä."), "not_allowed");
    if (a.professionalUse === true) need("attributes.professionalUse", l("Professional-use-only products can't be sold to consumers.", "Vain ammattikäyttöön tarkoitettuja tuotteita ei voi myydä kuluttajille."), "not_allowed");
    if (p.isSecondHand || p.condition !== "NEW") need("condition", l("Cosmetics must be new, sealed and unused.", "Kosmetiikan on oltava uutta, avaamatonta ja käyttämätöntä."), "not_allowed");
    if (!p.responsiblePerson) {
      need("responsiblePersonId", l("Add the cosmetics responsible person (name and address in the EU).", "Lisää kosmetiikan vastuuhenkilö (nimi ja osoite EU:ssa)."));
    } else if (!inEu(p.responsiblePerson.countryCode)) {
      need("responsiblePersonId", l("The cosmetics responsible person must be in the EU.", "Kosmetiikan vastuuhenkilön on oltava EU:ssa."), "not_in_eu");
    }
    if (t === "FRAGRANCE" && !a.concentration) warn("attributes.concentration", l("Add the concentration (e.g. eau de parfum).", "Lisää tuoksun vahvuus (esim. eau de parfum)."));
  }

  // Recommended (never blocking)
  if (t && !has(a.brand)) warn("attributes.brand", l("Add the brand, or \"No brand\".", "Lisää merkki tai \"Merkitön\"."));
  if (t && !isCosmetic(t) && t !== "BEAUTY_TOOL" && !a.colourFamily && !p.variants.some((v) => v.colourFamily)) {
    warn("attributes.colourFamily", l("Add the colour so shoppers can filter by it.", "Lisää väri, jotta ostajat voivat suodattaa sen mukaan."));
  }
  if (t === "APPAREL" && business && !Array.isArray(a.sizeChart)) warn("attributes.sizeChart", l("Add your size chart in cm.", "Lisää kokotaulukko senttimetreinä."));
  if (p.isSecondHand && ["GOOD", "FAIR", "POOR"].includes(p.condition) && !has(a.defectsNote)) {
    warn("attributes.defectsNote", l("Describe any wear or defects (or say there are none).", "Kuvaa käytön jäljet ja viat (tai kerro, ettei niitä ole)."));
  }

  return { ready: missing.length === 0, missing, warnings };
}

/** The 422 body for a refused publish, with the summary in the request's language. */
export function publishError(check: PublishCheck, locale: "fi" | "en") {
  const first = check.missing[0];
  const more = check.missing.length - 1;
  const summary = locale === "fi"
    ? `Tuotetta ei voi julkaista: ${first?.message.fi ?? "tietoja puuttuu"}${more > 0 ? ` (ja ${more} muuta)` : ""}`
    : `The product can't be published yet: ${first?.message.en ?? "information is missing"}${more > 0 ? ` (and ${more} more)` : ""}`;
  return { ok: false, code: "PUBLISH_REQUIREMENTS", error: summary, fields: check.missing, warnings: check.warnings };
}
