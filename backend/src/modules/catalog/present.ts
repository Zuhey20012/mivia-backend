import { compositionText } from "./attributes";
import { isLive, presentCertificate } from "./certificates";
import { inEu } from "./publish";
import { SUBS, TOPS } from "./taxonomy";
import { unitPriceFor } from "./unitPrice";
import { env } from "../../config/env";

/** A manufacturer / responsible person record as shoppers and owners see it. */
export function presentOperator(o: any) {
  if (!o) return null;
  return {
    id: o.id,
    name: o.name,
    address: { line: o.addressLine, postalCode: o.postalCode, city: o.city, countryCode: o.countryCode },
    email: o.email ?? null,
    url: o.url ?? null,
    phone: o.phone ?? null,
    inEu: inEu(o.countryCode),
  };
}

export const HYGIENE_NOTICE = {
  en: "Hygiene seal — can't be returned once the seal is opened. Unopened, you can return it within 14 days.",
  fi: "Hygieniasinetöity – ei palautusoikeutta, jos sinetti avataan. Avaamattoman tuotteen voit palauttaa 14 päivän kuluessa.",
};

const ANIMAL_NOTICE = {
  en: "Contains non-textile parts of animal origin",
  fi: "Sisältää muuta kuin tekstiiliä olevia eläinperäisiä osia",
};

/** Option-level catalogue data: colour family, shade, measurements, content and its unit price. */
export function presentOption(v: any, priceCents: number | null, product: any) {
  const amount = v.contentAmount ?? product.contentAmount ?? null;
  const unit = v.contentAmount ? v.contentUnit : product.contentUnit ?? null;
  return {
    colourFamily: v.colourFamily ?? null,
    shadeName: v.shadeName ?? null,
    shadeHex: v.shadeHex ?? null,
    shadeFamily: v.shadeFamily ?? null,
    undertone: v.undertone ?? null,
    finish: v.finish ?? null,
    measurements: v.measurements ?? null,
    contentAmount: v.contentAmount ?? null,
    contentUnit: v.contentUnit ?? null,
    unitPrice: unitPriceFor(priceCents, amount, unit),
  };
}

/** Product-level catalogue data (see the app contract in the 2.12.0 report). */
export function presentCatalog(p: any, priceCents: number | null, opts: { owner?: boolean }) {
  const cat = p.categoryRef ?? null;
  const sub = cat ? SUBS.get(cat.slug) : undefined;
  const top = sub ? TOPS.get(sub.top) : undefined;
  const attrs = (p.attributes ?? {}) as Record<string, any>;
  const warnings = p.warningsFi || p.warningsSv || p.warningsEn ? { fi: p.warningsFi ?? null, sv: p.warningsSv ?? null, en: p.warningsEn ?? null } : null;
  const certs = (p.certificates ?? []).map((pc: any) => pc.certificate).filter((c: any) => c && (opts.owner || isLive(c)));
  const recall = p.recalls?.[0]?.recall ?? null;
  const fi = compositionText(attrs.fibreComposition, "fi");
  return {
    categoryId: p.categoryId ?? null,
    categorySlug: cat?.slug ?? null,
    categoryName: cat ? { en: cat.nameEn, fi: cat.nameFi } : null,
    categoryPath: cat && top ? [{ slug: top.slug, name: { en: top.en, fi: top.fi } }, { slug: cat.slug, name: { en: cat.nameEn, fi: cat.nameFi } }] : [],
    template: cat?.template ?? null,
    audience: p.audience,
    attributes: attrs,
    // The label text of the material, shown before purchase (Reg. 1007/2011 Art. 16)
    materials: fi ? { en: compositionText(attrs.fibreComposition, "en"), fi } : null,
    animalOriginNotice: attrs.containsAnimalNonTextile === true ? ANIMAL_NOTICE : null,
    contentAmount: p.contentAmount ?? null,
    contentUnit: p.contentUnit ?? null,
    unitPrice: unitPriceFor(priceCents, p.contentAmount, p.contentUnit),
    hygieneSealed: !!p.hygieneSealed,
    hygieneSealNotice: p.hygieneSealed ? HYGIENE_NOTICE : null,
    safety: {
      manufacturer: presentOperator(p.manufacturer),
      responsiblePerson: presentOperator(p.responsiblePerson),
      productModel: p.productModel ?? null,
      gtin: p.gtin ?? null,
      batchOrSerial: p.batchOrSerial ?? null,
      warnings,
      noWarnings: !!p.noWarnings,
      images: p.safetyImages ?? [],
    },
    ...(opts.owner ? { manufacturerId: p.manufacturerId ?? null, responsiblePersonId: p.responsiblePersonId ?? null } : {}),
    certificates: certs.map((c: any) => presentCertificate(c, opts)),
    recall: recall ? { id: recall.id, title: recall.title, since: recall.createdAt, url: `${env.publicApiUrl}/recalls/${recall.id}` } : null,
  };
}
