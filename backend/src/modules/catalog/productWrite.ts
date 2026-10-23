import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { FieldIssue, attrsFor, validateAttributes } from "./attributes";
import { checkClaims, isGreenTag } from "./claims";
import { categoryIndex } from "./categories";
import { matchTaxonomy } from "./matcher";
import { PublishCandidate, PublishCheck, PublishStore, hygieneSealAllowed, publishCheck } from "./publish";
import { schemeFits } from "./certificates";
import { Template, isCosmetic } from "./taxonomy";

const l = (en: string, fi: string) => ({ en, fi });

/** 422 with field-level, bilingual messages (invalid category data, or publishing requirements not met). */
export class FieldsError extends ApiError {
  constructor(public code: string, public fields: FieldIssue[], public warnings: FieldIssue[] = []) {
    super(fields[0]?.message.en ?? "Invalid product data", 422);
  }
  body(locale: "fi" | "en") {
    const first = this.fields[0];
    const more = this.fields.length - 1;
    const lead = this.code === "PUBLISH_REQUIREMENTS"
      ? (locale === "fi" ? "Tuotetta ei voi vielä julkaista: " : "The product can't be published yet: ")
      : "";
    const msg = first ? first.message[locale] : locale === "fi" ? "Tarkista tuotteen tiedot." : "Check the product details.";
    const tail = more > 0 ? (locale === "fi" ? ` (ja ${more} muuta)` : ` (and ${more} more)`) : "";
    return { ok: false, code: this.code, error: `${lead}${msg}${tail}`, fields: this.fields, warnings: this.warnings };
  }
}

type StoreRow = PublishStore & { id: number };
type Operator = { id: number; storeId: number; countryCode: string };

/** The fields of a product row (with productInclude) that the publishing rules look at. */
export function candidateFromRow(row: any, recalled = false): PublishCandidate {
  return {
    name: row.name,
    description: row.description ?? null,
    tags: row.tags ?? [],
    categorySlug: row.categoryRef?.slug ?? null,
    template: (row.categoryRef?.template as Template) ?? null,
    audience: row.audience ?? "UNISEX",
    ageGroup: row.ageGroup ?? null,
    condition: row.condition ?? "NEW",
    isSecondHand: !!row.isSecondHand,
    attributes: (row.attributes ?? {}) as Record<string, any>,
    contentAmount: row.contentAmount ?? null,
    contentUnit: row.contentUnit ?? null,
    variants: (row.variants ?? []).map((v: any) => ({ contentAmount: v.contentAmount ?? null, contentUnit: v.contentUnit ?? null, colourFamily: v.colourFamily ?? null, size: v.size ?? null })),
    manufacturer: row.manufacturer ? { countryCode: row.manufacturer.countryCode } : null,
    responsiblePerson: row.responsiblePerson ? { countryCode: row.responsiblePerson.countryCode } : null,
    productModel: row.productModel ?? null,
    warningsFi: row.warningsFi ?? null,
    warningsSv: row.warningsSv ?? null,
    noWarnings: !!row.noWarnings,
    importHold: row.importHold ?? null,
    recalled,
  };
}

/** Owner views: whether the product could be published now, and what is missing (the completeness meter). */
export function ownerPublishCheck(row: any, store: PublishStore): PublishCheck {
  return publishCheck(candidateFromRow(row), store);
}

/** Is this GTIN, or this brand + model, part of an active recall? (identical listings cannot be re-listed) */
export async function isRecalledIdentity(gtin: string | null | undefined, brand: unknown, model: string | null | undefined, exceptProductId?: number) {
  const or: any[] = [];
  if (gtin) or.push({ gtin });
  if (typeof brand === "string" && brand.trim() && model && model.trim()) {
    or.push({ productModel: { equals: model.trim(), mode: "insensitive" }, facets: { some: { key: "brand", value: brand.trim().toLowerCase() } } });
  }
  if (!or.length) return false;
  const hit = await prisma.recallProduct.findFirst({
    where: { recall: { status: "ACTIVE" }, product: { OR: or }, ...(exceptProductId ? { productId: { not: exceptProductId } } : {}) },
    select: { recallId: true },
  });
  return !!hit;
}

export type Prepared = {
  /** Columns to write (catalogue inputs converted: categorySlug → categoryId + category, warnings → warningsFi/Sv/En) */
  data: Record<string, any>;
  certificateIds?: number[];
  /** Claims-checker hits on name/description (warnings on drafts; the blocking ones also stop publishing) */
  warnings: FieldIssue[];
  candidate: PublishCandidate;
  /** The GTIN the product will have (recall blocklist) */
  gtin: string | null;
};

/**
 * Validates and converts the catalogue part of a product create/update (also used by the importer). Throws a
 * FieldsError (422) for values that are wrong whatever the state (unknown attributes, a seal on clothing, someone else's
 * manufacturer record…); missing information is only checked when publishing.
 */
export async function prepareCatalogWrite(store: StoreRow, existing: any | null, input: Record<string, any>, opts: { mapLegacy?: boolean } = {}): Promise<Prepared> {
  const issues: FieldIssue[] = [];
  const {
    categorySlug, attributes, warnings, certificateIds, ...rest
  } = input;
  const data: Record<string, any> = { ...rest };
  const idx = await categoryIndex();

  // Category: an explicit subcategory slug, else (old app builds, imports) the legacy free text mapped with the import rules
  let node = existing?.categoryId ? idx.byId.get(existing.categoryId) ?? null : null;
  let categoryChanged = false;
  if (categorySlug !== undefined) {
    if (categorySlug === null) {
      node = null;
      categoryChanged = true;
    } else {
      const n = idx.bySlug.get(categorySlug);
      if (!n || !n.template || n.isCollection || !n.active) {
        issues.push({ field: "categorySlug", code: "invalid", message: l("Pick a subcategory from the list.", "Valitse alakategoria listasta.") });
      } else {
        categoryChanged = n.id !== existing?.categoryId;
        node = n;
      }
    }
    data.importHold = null; // the store chose the category itself
  } else if ((opts.mapLegacy ?? true) && !node && (input.category || input.name) && !existing?.categoryId) {
    const m = matchTaxonomy([input.category, input.name ?? existing?.name]);
    const n = m.slug ? idx.bySlug.get(m.slug) : undefined;
    if (n && n.active && n.template) { node = n; categoryChanged = true; }
  }
  if (node) data.categoryId = node.id;
  else if (categorySlug === null) data.categoryId = null;
  if (node && (categoryChanged || !existing)) data.category = node.nameEn;
  if (!existing && !data.category) data.category = node?.nameEn ?? "Uncategorised";
  const template = (node?.template as Template) ?? null;

  // Attributes: merged with what is stored (null removes a value); stored values that do not belong to a new template go
  let attrs: Record<string, any> = (existing?.attributes ?? {}) as Record<string, any>;
  if (categoryChanged && template) {
    const allowed = new Set(attrsFor(template).map((a) => a.key));
    attrs = Object.fromEntries(Object.entries(attrs).filter(([k]) => allowed.has(k)));
  }
  if (attributes !== undefined || categoryChanged) {
    const merged = { ...attrs, ...(attributes ?? {}) };
    const v = validateAttributes(template, merged);
    if (!v.ok) issues.push(...v.issues);
    else { attrs = v.value; data.attributes = attrs; }
  }

  // Hygiene seal: cosmetics, fragrance, sealed piercing jewellery / earrings only; on by default for those templates
  let sealed: boolean = input.hygieneSealed ?? existing?.hygieneSealed ?? false;
  if (!existing && input.hygieneSealed === undefined && (isCosmetic(template) || node?.slug === "jewellery-piercing")) sealed = true;
  if (sealed && !hygieneSealAllowed(node?.slug ?? null, template)) {
    if (input.hygieneSealed === true) {
      issues.push({ field: "hygieneSealed", code: "not_allowed", message: l(
        "A hygiene seal is only for sealed cosmetics, fragrance and piercing jewellery or earrings in sealed packs. Clothing can always be returned.",
        "Hygieniasinetti on vain sinetöidylle kosmetiikalle, tuoksuille sekä lävistyskoruille ja korvakoruille sinetöidyssä pakkauksessa. Vaatteet voi aina palauttaa.",
      ) });
    } else sealed = false; // moved out of a sealed category
  }
  if (sealed !== (existing?.hygieneSealed ?? false) || !existing) data.hygieneSealed = sealed;

  // Content: amount and unit together
  const amount = input.contentAmount !== undefined ? input.contentAmount : existing?.contentAmount ?? null;
  const unit = input.contentUnit !== undefined ? input.contentUnit : existing?.contentUnit ?? null;
  if (!!amount !== !!unit) issues.push({ field: "contentAmount", code: "invalid", message: l("Give the content with its unit (ml, g or pcs).", "Anna sisältö yksikköineen (ml, g tai kpl).") });
  for (const [i, v] of (input.variants ?? []).entries()) {
    if (!!v.contentAmount !== !!v.contentUnit) issues.push({ field: `variants.${i}.contentAmount`, code: "invalid", message: l("Give the option's content with its unit.", "Anna vaihtoehdon sisältö yksikköineen.") });
  }

  // Audience and age group: baby–junior are children; adult is not
  const audience = input.audience ?? existing?.audience ?? "UNISEX";
  const ageGroup = input.ageGroup !== undefined ? input.ageGroup : existing?.ageGroup ?? null;
  if (ageGroup && ["BABY", "TODDLER", "KIDS", "JUNIOR"].includes(ageGroup) && audience !== "KIDS") {
    issues.push({ field: "ageGroup", code: "invalid", message: l("Baby, toddler, kids and junior sizes are for the Kids audience.", "Vauva-, taapero-, lasten- ja junioriikäryhmät kuuluvat lapsille.") });
  }
  if (ageGroup === "ADULT" && audience === "KIDS") issues.push({ field: "ageGroup", code: "invalid", message: l("An adult product can't be for kids.", "Aikuisten tuote ei voi olla lapsille.") });
  // Kids' sizes in cm: with the kids' height size system an option size is a height 50–176
  if (audience === "KIDS" && attrs.sizeSystem === "kids_height") {
    for (const [i, v] of ((input.variants ?? existing?.variants ?? []) as any[]).entries()) {
      const n = Number(String(v.size ?? "").replace(/\s*cm$/i, ""));
      if (v.size && !(Number.isInteger(n) && n >= 50 && n <= 176)) {
        issues.push({ field: `variants.${i}.size`, code: "invalid", message: l("Kids' sizes are heights in cm, 50–176 (e.g. 110).", "Lasten koot ovat pituuksia senttimetreinä, 50–176 (esim. 110).") });
      }
    }
  }

  // Manufacturer / responsible person records must be the store's own
  const opIds = [input.manufacturerId, input.responsiblePersonId].filter((x): x is number => typeof x === "number");
  const ops: Operator[] = opIds.length ? await prisma.economicOperator.findMany({ where: { id: { in: opIds } }, select: { id: true, storeId: true, countryCode: true } }) : [];
  const own = (id: number | null | undefined) => (typeof id === "number" ? ops.find((o) => o.id === id && o.storeId === store.id) ?? null : null);
  for (const key of ["manufacturerId", "responsiblePersonId"] as const) {
    if (typeof input[key] === "number" && !own(input[key])) {
      issues.push({ field: key, code: "unknown", message: l("Pick one of your own manufacturer / responsible person records.", "Valitse jokin omista valmistaja- tai vastuuhenkilötiedoistasi.") });
    }
  }

  // Warnings and safety information as on the label: { fi, sv, en }
  if (warnings !== undefined) {
    data.warningsFi = warnings?.fi?.trim() || null;
    data.warningsSv = warnings?.sv?.trim() || null;
    data.warningsEn = warnings?.en?.trim() || null;
    if (data.warningsFi || data.warningsSv) data.noWarnings = input.noWarnings ?? false;
  }
  if (data.gtin === "") data.gtin = null;

  // Certificates: the store's own; the scheme must fit the category (e.g. Leaping Bunny only for cosmetics)
  let certIds: number[] | undefined;
  if (certificateIds !== undefined) {
    certIds = [...new Set(certificateIds as number[])];
    const certs = certIds.length ? await prisma.certificate.findMany({ where: { id: { in: certIds } }, select: { id: true, storeId: true, scheme: true } }) : [];
    for (const id of certIds) {
      const c = certs.find((x) => x.id === id);
      if (!c || c.storeId !== store.id) issues.push({ field: "certificateIds", code: "unknown", message: l("Pick one of your own certificates.", "Valitse jokin omista sertifikaateistasi.") });
      else if (!schemeFits(c.scheme, template)) issues.push({ field: "certificateIds", code: "not_for_category", message: l("This certificate scheme does not cover this kind of product.", "Tämä sertifiointijärjestelmä ei koske tällaista tuotetta.") });
    }
  }

  // Generic green words are never stored as tags; in the name or description they are warnings (and block publishing)
  if (Array.isArray(data.tags)) data.tags = data.tags.filter((t: string) => !isGreenTag(t));
  if (issues.length) throw new FieldsError("INVALID_PRODUCT_DATA", issues);

  const claims = checkClaims({ name: input.name ?? existing?.name, description: input.description !== undefined ? input.description : existing?.description });
  const claimWarnings: FieldIssue[] = claims.map((c) => ({ field: c.field, code: c.blocking ? "generic_green_claim" : "check_claim", message: c.message }));

  const manufacturer = input.manufacturerId !== undefined ? own(input.manufacturerId) : existing?.manufacturer ?? null;
  const responsible = input.responsiblePersonId !== undefined ? own(input.responsiblePersonId) : existing?.responsiblePerson ?? null;
  const view = {
    ...(existing ?? {}),
    ...data,
    attributes: attrs,
    contentAmount: amount,
    contentUnit: unit,
    variants: input.variants ?? existing?.variants ?? [],
    categoryRef: node ? { slug: node.slug, template: node.template } : null,
    manufacturer,
    responsiblePerson: responsible,
  };
  const gtin = data.gtin !== undefined ? data.gtin : existing?.gtin ?? null;
  return { data, certificateIds: certIds, warnings: claimWarnings, candidate: candidateFromRow(view), gtin };
}

/** Throws the 422 PUBLISH_REQUIREMENTS error when the product cannot be visible yet. */
export async function assertPublishable(prepared: Prepared, store: StoreRow, productId?: number) {
  const c = prepared.candidate;
  c.recalled = await isRecalledIdentity(prepared.gtin, c.attributes.brand, c.productModel, productId);
  const check = publishCheck(c, store);
  if (!check.ready) throw new FieldsError("PUBLISH_REQUIREMENTS", check.missing, check.warnings);
  return check;
}
