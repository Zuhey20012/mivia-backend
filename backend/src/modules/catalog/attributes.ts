import { z } from "zod";
import { Template, TEMPLATES, isCosmetic } from "./taxonomy";

/**
 * Category-specific product data (spec §2): one descriptor per attribute, from which the per-template zod schemas, the
 * facet (filter) keys and the labels the apps show are all derived. Product.attributes holds the product-level values;
 * option-level values (shade, colour family, content, measurements) are columns on ProductVariant.
 */

type L = { en: string; fi: string };
const l = (en: string, fi: string): L => ({ en, fi });

// ─── Allowed values ──────────────────────────────────────────────────────────

/** Regulation (EU) No 1007/2011 Annex I fibre names (key → EN / FI). The shop picks from this list, never free text. */
export const FIBRES: Record<string, L> = {
  wool: l("wool", "villa"), alpaca: l("alpaca", "alpakka"), llama: l("llama", "laama"), camel: l("camel", "kameli"),
  cashmere: l("cashmere", "kashmir"), mohair: l("mohair", "mohair"), angora: l("angora", "angora"), vicuna: l("vicuna", "vikunja"),
  yak: l("yak", "jakki"), guanaco: l("guanaco", "guanako"), cashgora: l("cashgora", "cashgora"), beaver: l("beaver", "majava"),
  otter: l("otter", "saukko"), animal_hair: l("animal hair", "eläimen karva"), horsehair: l("horsehair", "jouhi"),
  silk: l("silk", "silkki"), cotton: l("cotton", "puuvilla"), kapok: l("kapok", "kapokki"), flax: l("flax (linen)", "pellava"),
  hemp: l("true hemp", "hamppu"), jute: l("jute", "juutti"), abaca: l("abaca (Manila hemp)", "manilla"), alfa: l("alfa", "esparto (alfaheinä)"),
  coir: l("coir (coconut)", "kookos"), broom: l("broom", "genista"), ramie: l("ramie", "rami"), sisal: l("sisal", "sisali"),
  sunn: l("sunn", "sunhamppu"), henequen: l("henequen", "henequen"), maguey: l("maguey", "maguey"),
  acetate: l("acetate", "asetaatti"), alginate: l("alginate", "alginaatti"), cupro: l("cupro", "kupro"), modal: l("modal", "modaali"),
  protein: l("protein", "proteiini"), triacetate: l("triacetate", "triasetaatti"), viscose: l("viscose", "viskoosi"),
  acrylic: l("acrylic", "akryyli"), chlorofibre: l("chlorofibre", "klorokuitu"), fluorofibre: l("fluorofibre", "fluorokuitu"),
  modacrylic: l("modacrylic", "modakryyli"), polyamide: l("polyamide or nylon", "polyamidi tai nailon"), aramid: l("aramid", "aramidi"),
  polyimide: l("polyimide", "polyimidi"), lyocell: l("lyocell", "lyocell"), polylactide: l("polylactide", "polylaktidi"),
  polyester: l("polyester", "polyesteri"), polyethylene: l("polyethylene", "polyeteeni"), polypropylene: l("polypropylene", "polypropeeni"),
  polycarbamide: l("polycarbamide", "polyurea"), polyurethane: l("polyurethane", "polyuretaani"), vinylal: l("vinylal", "vinylaali"),
  trivinyl: l("trivinyl", "trivinyyli"), elastodiene: l("elastodiene", "elastodieeni"), elastane: l("elastane", "elastaani"),
  glass_fibre: l("glass fibre", "tekstiililasi"), elastomultiester: l("elastomultiester", "elastomultiesteri"),
  elastolefin: l("elastolefin", "elasto-olefiini"), melamine: l("melamine", "melamiini"), other_fibres: l("other fibres", "muut kuidut"),
};
const FIBRE_KEYS = Object.keys(FIBRES) as [string, ...string[]];

export const COLOUR_FAMILIES = ["black", "white", "grey", "beige", "brown", "blue", "navy", "green", "red", "pink", "purple", "yellow", "orange", "gold", "silver", "multi"] as const;
export const SHADE_FAMILIES = ["very_fair", "fair", "light", "light_medium", "medium", "medium_tan", "tan", "deep", "very_deep", "nude", "pink", "red", "coral", "berry", "plum", "brown", "orange", "purple", "blue", "green", "black", "white", "clear", "glitter", "metallic"] as const;
export const UNDERTONES = ["cool", "neutral", "warm", "olive"] as const;
export const FINISHES = ["matte", "satin", "natural", "dewy", "glossy", "shimmer", "metallic"] as const;
export const CONTENT_UNITS = ["ml", "g", "pcs"] as const;
const COMPONENTS = ["main", "lining", "filling", "outer", "inner", "trim", "other"] as const;
const FOOT_MATERIALS = ["leather", "coated_leather", "textile", "other"] as const;
const MEASUREMENT_KEYS = ["chest", "bust", "waist", "hips", "insideLeg", "height", "neck", "length", "chestWidth", "sleeve", "footLengthCm", "headCircumferenceCm", "innerDiameterMm"] as const;

/** Labels for enum values shown in filters and on product pages. Values not listed fall back to the key, humanised. */
export const VALUE_LABELS: Record<string, L> = {
  // colours
  black: l("Black", "Musta"), white: l("White", "Valkoinen"), grey: l("Grey", "Harmaa"), beige: l("Beige", "Beige"),
  brown: l("Brown", "Ruskea"), blue: l("Blue", "Sininen"), navy: l("Navy", "Tummansininen"), green: l("Green", "Vihreä"),
  red: l("Red", "Punainen"), pink: l("Pink", "Pinkki"), purple: l("Purple", "Violetti"), yellow: l("Yellow", "Keltainen"),
  orange: l("Orange", "Oranssi"), gold: l("Gold", "Kulta"), silver: l("Silver", "Hopea"), multi: l("Multicolour", "Monivärinen"),
  // shade families
  very_fair: l("Very fair", "Hyvin vaalea"), fair: l("Fair", "Vaalea"), light: l("Light", "Kevyt / vaalea"), light_medium: l("Light–medium", "Vaalea–keskisävy"),
  medium: l("Medium", "Keskisävy"), medium_tan: l("Medium–tan", "Keskisävy–ruskettunut"), tan: l("Tan", "Ruskettunut"), deep: l("Deep", "Tumma"),
  very_deep: l("Very deep", "Hyvin tumma"), nude: l("Nude", "Nude"), coral: l("Coral", "Koralli"), berry: l("Berry", "Marja"),
  plum: l("Plum", "Luumu"), clear: l("Clear", "Kirkas"), glitter: l("Glitter", "Glitter"), metallic: l("Metallic", "Metallinen"),
  // undertone, finish
  cool: l("Cool", "Viileä"), neutral: l("Neutral", "Neutraali"), warm: l("Warm", "Lämmin"), olive: l("Olive", "Oliivi"),
  matte: l("Matte", "Mattapintainen"), satin: l("Satin", "Satiini"), natural: l("Natural", "Luonnollinen"), dewy: l("Dewy", "Kostea / hehkuva"),
  glossy: l("Glossy", "Kiiltävä"), shimmer: l("Shimmer", "Shimmer"),
  // skin and hair
  all: l("All", "Kaikki"), dry: l("Dry", "Kuiva"), oily: l("Oily", "Rasvoittuva"), combination: l("Combination", "Seka-iho"),
  normal: l("Normal", "Normaali"), sensitive: l("Sensitive", "Herkkä"), mature: l("Mature", "Kypsä"),
  fine: l("Fine", "Ohut"), thick: l("Thick", "Paksu"), curly: l("Curly", "Kihara"), coily: l("Coily", "Kierteinen"),
  straight: l("Straight", "Suora"), coloured: l("Coloured", "Värjätty"), damaged: l("Damaged", "Vaurioitunut"),
  // fragrance
  parfum: l("Parfum", "Parfyymi"), eau_de_parfum: l("Eau de parfum", "Eau de parfum"), eau_de_toilette: l("Eau de toilette", "Eau de toilette"),
  eau_de_cologne: l("Eau de cologne", "Eau de cologne"), body_mist: l("Body mist", "Vartalosuihke"), perfume_oil: l("Perfume oil", "Tuoksuöljy"),
  // metals
  white_gold: l("White gold", "Valkokulta"), rose_gold: l("Rose gold", "Punakulta"), silver_925: l("Silver 925", "Hopea 925"),
  sterling_silver: l("Sterling silver", "Sterling-hopea"), platinum: l("Platinum", "Platina"), palladium: l("Palladium", "Palladium"),
  stainless_steel_316l: l("Stainless steel 316L", "Ruostumaton teräs 316L"), titanium: l("Titanium", "Titaani"), brass: l("Brass", "Messinki"),
  copper: l("Copper", "Kupari"), aluminium: l("Aluminium", "Alumiini"), alloy_unknown: l("Alloy (unknown)", "Seos (tuntematon)"), none: l("None", "Ei"),
  // materials
  leather: l("Leather", "Nahka"), coated_leather: l("Coated leather", "Pinnoitettu nahka"), textile: l("Textile", "Tekstiili"), other: l("Other", "Muu"),
  synthetic_leather: l("Synthetic leather", "Tekonahka"), plastic: l("Plastic", "Muovi"), metal: l("Metal", "Metalli"), wood: l("Wood", "Puu"), straw: l("Straw", "Olki"),
  // conditions and audiences
  NEW: l("New", "Uusi"), LIKE_NEW: l("Like new", "Kuin uusi"), GOOD: l("Good", "Hyvä"), FAIR: l("Fair", "Kohtalainen"), POOR: l("Worn", "Kulunut"),
  WOMEN: l("Women", "Naiset"), MEN: l("Men", "Miehet"), KIDS: l("Kids", "Lapset"), UNISEX: l("Unisex", "Unisex"),
  true: l("Yes", "Kyllä"),
};
export function valueLabel(v: string): L {
  return VALUE_LABELS[v] ?? FIBRES[v] ?? { en: v.replace(/_/g, " "), fi: v.replace(/_/g, " ") };
}

// ─── Descriptors ─────────────────────────────────────────────────────────────

type Kind = "enum" | "enums" | "text" | "int" | "number" | "bool" | "i18n" | "composition" | "sizeChart" | "care" | "dimensions" | "month" | "strings";
export type AttrDef = {
  key: string;
  label: L;
  kind: Kind;
  values?: readonly (string | number)[];
  max?: number;
  min?: number;
  maxItems?: number;
  templates: readonly Template[] | "ALL";
  /** Filterable: written to ProductFacet and offered in GET /categories/:slug facets */
  facet?: boolean;
  /** "law" | "malvoya" | "optional": informational for the editor (the publish rules in publish.ts decide) */
  level?: "law" | "malvoya" | "optional";
};

const APP: Template[] = ["APPAREL"];
const TEXTILE: Template[] = ["APPAREL", "APPAREL_ACCESSORY"];
const WEARABLE: Template[] = ["APPAREL", "APPAREL_ACCESSORY", "FOOTWEAR"];
const BAGS: Template[] = ["BAG", "ACCESSORY"];
const COSM = ["COSMETIC_MAKEUP", "COSMETIC_SKIN", "COSMETIC_HAIR", "COSMETIC_NAIL", "FRAGRANCE"] as Template[];
const SHADE: Template[] = ["COSMETIC_MAKEUP", "COSMETIC_NAIL"];
const NON_BEAUTY: Template[] = ["APPAREL", "APPAREL_ACCESSORY", "FOOTWEAR", "BAG", "ACCESSORY", "EYEWEAR", "WATCH", "JEWELLERY"];

export const ATTRS: AttrDef[] = [
  // COMMON
  { key: "brand", label: l("Brand", "Merkki"), kind: "text", max: 60, templates: "ALL", level: "malvoya" },
  { key: "countryOfManufacture", label: l("Made in", "Valmistusmaa"), kind: "text", max: 2, min: 2, templates: "ALL", facet: true },
  { key: "colourFamily", label: l("Colour", "Väri"), kind: "enum", values: COLOUR_FAMILIES, templates: NON_BEAUTY, facet: true, level: "malvoya" },
  { key: "colourName", label: l("Colour name", "Värin nimi"), kind: "text", max: 40, templates: NON_BEAUTY },
  { key: "pattern", label: l("Pattern", "Kuosi"), kind: "enum", values: ["plain", "striped", "checked", "floral", "animal", "dotted", "graphic", "other"], templates: [...TEXTILE, ...BAGS], facet: true },
  { key: "season", label: l("Season", "Kausi"), kind: "enums", values: ["spring", "summer", "autumn", "winter", "all"], templates: WEARABLE, facet: true },
  { key: "productType", label: l("Type", "Tyyppi"), kind: "text", max: 40, templates: [...COSM, "BEAUTY_TOOL"], facet: true },
  // second-hand condition (§2.13)
  { key: "defectsNote", label: l("Defects", "Viat"), kind: "text", max: 300, templates: NON_BEAUTY },
  { key: "hasTags", label: l("With tags", "Hintalappu tallella"), kind: "bool", templates: NON_BEAUTY },
  { key: "originalSizeLabel", label: l("Size on the label", "Koko lapussa"), kind: "text", max: 40, templates: NON_BEAUTY },
  { key: "authenticity", label: l("Authenticity", "Aitous"), kind: "enum", values: ["receipt", "original_packaging_and_cards", "authentication_service_report", "none"], templates: NON_BEAUTY },
  { key: "brandTier", label: l("Designer", "Merkkituote"), kind: "enum", values: ["designer"], templates: NON_BEAUTY, facet: true },
  { key: "vintage", label: l("Vintage (20+ years old)", "Vintage (yli 20 vuotta)"), kind: "bool", templates: NON_BEAUTY, facet: true },
  { key: "hygieneSealDescription", label: l("What the seal is", "Sinetin kuvaus"), kind: "enum", values: ["shrink_wrap", "sealed_cap_or_foil", "sealed_box", "sealed_pouch"], templates: [...COSM, "JEWELLERY"] },

  // APPAREL and textile accessories (§2.2, §2.3)
  { key: "fibreComposition", label: l("Material", "Materiaali"), kind: "composition", templates: [...TEXTILE, ...BAGS], level: "law" },
  { key: "containsAnimalNonTextile", label: l("Contains non-textile parts of animal origin", "Sisältää muuta kuin tekstiiliä olevia eläinperäisiä osia"), kind: "bool", templates: [...TEXTILE, ...BAGS], level: "law" },
  { key: "fibreCompositionUnknown", label: l("Material label missing", "Materiaalimerkintä puuttuu"), kind: "bool", templates: [...TEXTILE, ...BAGS] },
  { key: "textileUnder80", label: l("Less than 80 % textile by weight (e.g. leather gloves)", "Alle 80 % tekstiiliä painosta (esim. nahkakäsineet)"), kind: "bool", templates: ["APPAREL_ACCESSORY", ...BAGS] },
  { key: "sizeSystem", label: l("Size system", "Kokojärjestelmä"), kind: "enum", values: ["letter", "eu_numeric", "jeans_wl", "kids_height", "one_size", "bra", "eu", "uk", "us_w", "us_m", "kids_eu", "head_cm", "glove"], templates: WEARABLE, level: "malvoya" },
  { key: "sizeChart", label: l("Size chart", "Kokotaulukko"), kind: "sizeChart", templates: WEARABLE },
  { key: "fit", label: l("Fit", "Istuvuus"), kind: "enum", values: ["slim", "regular", "relaxed", "oversized", "skinny", "straight", "wide", "flared"], templates: APP, facet: true },
  { key: "modelHeightCm", label: l("Model's height (cm)", "Mallin pituus (cm)"), kind: "int", min: 50, max: 230, templates: APP },
  { key: "modelSizeWorn", label: l("Size the model wears", "Mallin käyttämä koko"), kind: "text", max: 20, templates: APP },
  { key: "lengthType", label: l("Length", "Pituus"), kind: "enum", values: ["cropped", "regular", "long", "mini", "knee", "midi", "maxi"], templates: APP, facet: true },
  { key: "sleeveLength", label: l("Sleeves", "Hihat"), kind: "enum", values: ["sleeveless", "short", "three_quarter", "long"], templates: APP, facet: true },
  { key: "neckline", label: l("Neckline", "Pääntie"), kind: "enum", values: ["round", "v_neck", "high", "collar", "hood", "off_shoulder", "square"], templates: APP, facet: true },
  { key: "lining", label: l("Lining", "Vuori"), kind: "enum", values: ["none", "partial", "full"], templates: TEXTILE },
  { key: "careInstructions", label: l("Care", "Hoito-ohjeet"), kind: "care", templates: TEXTILE },
  { key: "occasion", label: l("Occasion", "Käyttötilanne"), kind: "enums", values: ["everyday", "party", "work", "sport", "outdoor", "home"], templates: APP, facet: true },
  // KIDS_SAFETY (§2.11), for audience KIDS
  { key: "ageRange", label: l("Age", "Ikä"), kind: "text", max: 30, templates: WEARABLE },
  { key: "cordsDrawstrings", label: l("Cords and drawstrings", "Narut ja kiristysnyörit"), kind: "enum", values: ["none", "compliant_en14682", "present_hood_neck"], templates: TEXTILE, level: "malvoya" },
  { key: "smallParts", label: l("Small detachable parts", "Irtoavat pienet osat"), kind: "enum", values: ["none", "secure_tested", "present"], templates: WEARABLE },
  { key: "costumeIsToy", label: l("Fancy-dress costume", "Naamiaisasu"), kind: "bool", templates: TEXTILE },

  // FOOTWEAR (§2.4, Directive 94/11/EC)
  { key: "materialUpper", label: l("Upper", "Päällinen"), kind: "enums", values: FOOT_MATERIALS, maxItems: 2, templates: ["FOOTWEAR"], facet: true, level: "law" },
  { key: "materialLiningSock", label: l("Lining and insole", "Vuori ja sisäpohja"), kind: "enums", values: FOOT_MATERIALS, maxItems: 2, templates: ["FOOTWEAR"], level: "law" },
  { key: "materialOuterSole", label: l("Outer sole", "Ulkopohja"), kind: "enums", values: FOOT_MATERIALS, maxItems: 2, templates: ["FOOTWEAR"], level: "law" },
  { key: "materialDetail", label: l("Material details", "Materiaalitiedot"), kind: "text", max: 120, templates: ["FOOTWEAR"] },
  { key: "width", label: l("Width", "Lesti"), kind: "enum", values: ["narrow", "standard", "wide", "extra_wide"], templates: ["FOOTWEAR"], facet: true },
  { key: "heelHeightCm", label: l("Heel height (cm)", "Korkeus (cm)"), kind: "number", min: 0, max: 30, templates: ["FOOTWEAR"] },
  { key: "closure", label: l("Fastening", "Kiinnitys"), kind: "enum", values: ["laces", "velcro", "zip", "slip_on", "buckle", "magnet", "open", "drawstring"], templates: ["FOOTWEAR", ...BAGS], facet: true },
  { key: "waterproof", label: l("Waterproof", "Vedenpitävä"), kind: "enum", values: ["no", "water_repellent", "waterproof_membrane"], templates: ["FOOTWEAR"], facet: true },
  { key: "linedWarm", label: l("Warm lining", "Lämmin vuori"), kind: "bool", templates: ["FOOTWEAR"], facet: true },

  // BAG and ACCESSORY (§2.5)
  { key: "mainMaterial", label: l("Material", "Materiaali"), kind: "enums", values: ["leather", "coated_leather", "textile", "synthetic_leather", "plastic", "metal", "wood", "straw", "other"], templates: [...BAGS, "BEAUTY_TOOL"], facet: true, level: "malvoya" },
  { key: "dimensionsCm", label: l("Size (W × H × D, cm)", "Mitat (L × K × S, cm)"), kind: "dimensions", templates: BAGS },
  { key: "strap", label: l("Strap", "Hihna"), kind: "enums", values: ["handle", "shoulder", "crossbody_adjustable", "backpack", "none"], templates: ["BAG"], facet: true },
  { key: "laptopFitsInch", label: l("Laptop fits (in)", "Kannettava mahtuu (tuumaa)"), kind: "int", min: 10, max: 20, templates: ["BAG"] },
  { key: "metalSkinContact", label: l("Metal parts touching skin", "Ihoa koskettavat metalliosat"), kind: "bool", templates: ["ACCESSORY", "WATCH"] },

  // EYEWEAR and WATCH (§2.6)
  { key: "uvFilterCategory", label: l("UV filter category", "UV-suojaluokka"), kind: "int", min: 0, max: 4, templates: ["EYEWEAR"], facet: true, level: "law" },
  { key: "ceMarked", label: l("CE marked", "CE-merkitty"), kind: "bool", templates: ["EYEWEAR"], level: "law" },
  { key: "polarised", label: l("Polarised", "Polarisoitu"), kind: "bool", templates: ["EYEWEAR"], facet: true },
  { key: "frameMaterial", label: l("Frame material", "Kehyksen materiaali"), kind: "text", max: 60, templates: ["EYEWEAR"] },
  { key: "movement", label: l("Movement", "Koneisto"), kind: "enum", values: ["quartz", "automatic", "mechanical", "smart"], templates: ["WATCH"], facet: true },
  { key: "caseMaterial", label: l("Case material", "Kotelon materiaali"), kind: "text", max: 60, templates: ["WATCH"] },
  { key: "strapMaterial", label: l("Strap material", "Rannekkeen materiaali"), kind: "text", max: 60, templates: ["WATCH"] },
  { key: "waterResistance", label: l("Water resistance", "Vesitiiviys"), kind: "enum", values: ["none", "3atm", "5atm", "10atm", "20atm"], templates: ["WATCH"], facet: true },
  { key: "containsBattery", label: l("Contains a battery", "Sisältää pariston"), kind: "bool", templates: ["WATCH"] },

  // JEWELLERY (§2.10, REACH Annex XVII)
  { key: "metal", label: l("Metal", "Metalli"), kind: "enum", values: ["gold", "white_gold", "rose_gold", "silver_925", "sterling_silver", "platinum", "palladium", "stainless_steel_316l", "titanium", "brass", "copper", "aluminium", "alloy_unknown", "none"], templates: ["JEWELLERY"], facet: true, level: "malvoya" },
  { key: "fineness", label: l("Fineness", "Pitoisuus"), kind: "enum", values: [375, 585, 750, 916, 999, 800, 830, 925, 950], templates: ["JEWELLERY"] },
  { key: "plating", label: l("Plating", "Pinnoite"), kind: "enum", values: ["none", "gold_plated", "gold_vermeil", "rhodium_plated", "silver_plated", "pvd"], templates: ["JEWELLERY"], facet: true },
  { key: "nickelBasis", label: l("Nickel safety", "Nikkeliturvallisuus"), kind: "enum", values: ["test_report_en1811", "supplier_declaration", "nickel_free_material", "not_known"], templates: ["JEWELLERY"], level: "law" },
  { key: "leadCadmiumBasis", label: l("Lead and cadmium", "Lyijy ja kadmium"), kind: "enum", values: ["supplier_declaration", "test_report", "precious_metal_only"], templates: ["JEWELLERY"], level: "malvoya" },
  { key: "stone", label: l("Stone", "Kivi"), kind: "enums", values: ["none", "diamond", "lab_diamond", "sapphire", "ruby", "emerald", "pearl", "freshwater_pearl", "crystal_glass", "cubic_zirconia", "semi_precious", "synthetic"], templates: ["JEWELLERY"], facet: true },
  { key: "chainLengthCm", label: l("Length (cm)", "Pituus (cm)"), kind: "number", min: 1, max: 200, templates: ["JEWELLERY"] },
  { key: "forPiercing", label: l("For pierced ears / body", "Lävistykseen"), kind: "bool", templates: ["JEWELLERY"] },
  { key: "hallmarked", label: l("Hallmarked", "Leimattu"), kind: "bool", templates: ["JEWELLERY"] },

  // COSMETIC (§2.7, Reg. 1223/2009 Art. 19)
  { key: "countryOfOrigin", label: l("Country of origin", "Alkuperämaa"), kind: "text", min: 2, max: 2, templates: COSM },
  { key: "durabilityType", label: l("Shelf life", "Säilyvyys"), kind: "enum", values: ["best_before", "pao", "not_relevant"], templates: COSM, level: "law" },
  { key: "paoMonths", label: l("After opening (months)", "Avaamisen jälkeen (kk)"), kind: "enum", values: [3, 6, 9, 12, 18, 24, 36], templates: COSM, level: "law" },
  { key: "bestBefore", label: l("Best before", "Parasta ennen"), kind: "month", templates: COSM, level: "law" },
  { key: "function", label: l("What it is for", "Käyttötarkoitus"), kind: "i18n", max: 500, templates: COSM, level: "law" },
  { key: "howToUse", label: l("How to use", "Käyttöohje"), kind: "i18n", max: 2000, templates: COSM },
  { key: "precautions", label: l("Precautions", "Varotoimet"), kind: "i18n", max: 2000, templates: COSM, level: "law" },
  { key: "noPrecautions", label: l("No precautions on the label", "Pakkauksessa ei varotoimia"), kind: "bool", templates: COSM },
  { key: "ingredientsInci", label: l("Ingredients", "Ainesosat"), kind: "text", max: 6000, templates: COSM, level: "malvoya" },
  { key: "keyIngredients", label: l("Key ingredients", "Pääainesosat"), kind: "enums", maxItems: 5, values: ["hyaluronic_acid", "niacinamide", "retinol", "vitamin_c", "ceramides", "salicylic_acid", "glycolic_acid", "peptides", "spf_filters", "shea_butter"], templates: COSM, facet: true },
  { key: "freeFrom", label: l("Free from", "Ei sisällä"), kind: "enums", values: ["fragrance", "alcohol", "animal_derived", "acetone"], templates: COSM, facet: true },
  { key: "skinType", label: l("Skin type", "Ihotyyppi"), kind: "enums", values: ["all", "dry", "oily", "combination", "normal", "sensitive", "mature"], templates: ["COSMETIC_SKIN", "COSMETIC_MAKEUP"], facet: true },
  { key: "skinConcern", label: l("Concern", "Huolenaihe"), kind: "enums", values: ["hydration", "dullness", "uneven_tone", "blemishes", "pores", "fine_lines", "redness", "dark_circles"], templates: ["COSMETIC_SKIN"], facet: true },
  { key: "hairType", label: l("Hair type", "Hiustyyppi"), kind: "enums", values: ["all", "fine", "thick", "curly", "coily", "straight", "coloured", "damaged", "oily", "dry"], templates: ["COSMETIC_HAIR"], facet: true },
  { key: "spf", label: l("SPF", "Suojakerroin"), kind: "enum", values: ["6", "10", "15", "20", "25", "30", "50", "50+"], templates: ["COSMETIC_SKIN", "COSMETIC_MAKEUP"], facet: true },
  { key: "coverage", label: l("Coverage", "Peittävyys"), kind: "enum", values: ["sheer", "light", "medium", "full"], templates: SHADE, facet: true },
  { key: "formulation", label: l("Texture", "Koostumus"), kind: "enum", values: ["liquid", "cream", "powder", "stick", "gel", "mousse", "pencil"], templates: SHADE, facet: true },
  { key: "finish", label: l("Finish", "Viimeistely"), kind: "enum", values: FINISHES, templates: SHADE, facet: true },
  { key: "professionalUse", label: l("Professional use only", "Vain ammattikäyttöön"), kind: "bool", templates: COSM },
  { key: "isTesterOrSample", label: l("Tester or sample", "Testeri tai näyte"), kind: "bool", templates: COSM },
  { key: "sealedUnused", label: l("Sealed and unused", "Avaamaton ja käyttämätön"), kind: "bool", templates: COSM, level: "malvoya" },
  // FRAGRANCE (§2.9)
  { key: "concentration", label: l("Concentration", "Tuoksun vahvuus"), kind: "enum", values: ["parfum", "eau_de_parfum", "eau_de_toilette", "eau_de_cologne", "body_mist", "perfume_oil"], templates: ["FRAGRANCE"], facet: true, level: "malvoya" },
  { key: "olfactoryFamily", label: l("Scent family", "Tuoksuperhe"), kind: "enums", maxItems: 2, values: ["floral", "fruity", "citrus", "green", "aromatic", "woody", "oriental_amber", "gourmand", "musky", "aquatic", "leather", "chypre", "fougere", "spicy"], templates: ["FRAGRANCE"], facet: true },
  { key: "notesTop", label: l("Top notes", "Lähtötuoksut"), kind: "strings", maxItems: 6, max: 40, templates: ["FRAGRANCE"] },
  { key: "notesHeart", label: l("Heart notes", "Sydäntuoksut"), kind: "strings", maxItems: 6, max: 40, templates: ["FRAGRANCE"] },
  { key: "notesBase", label: l("Base notes", "Pohjatuoksut"), kind: "strings", maxItems: 6, max: 40, templates: ["FRAGRANCE"] },
  { key: "launchYear", label: l("Launched", "Julkaisuvuosi"), kind: "int", min: 1900, max: 2100, templates: ["FRAGRANCE"] },
  { key: "refillable", label: l("Refillable", "Täytettävä"), kind: "bool", templates: ["FRAGRANCE"] },
  { key: "giftSet", label: l("Gift set", "Lahjapakkaus"), kind: "bool", templates: ["FRAGRANCE"], facet: true },
];

const DEFS = new Map(ATTRS.map((a) => [a.key, a]));
export const attrDef = (key: string) => DEFS.get(key);

export function attrsFor(template: Template): AttrDef[] {
  return ATTRS.filter((a) => a.templates === "ALL" || a.templates.includes(template));
}

// ─── Zod schemas ─────────────────────────────────────────────────────────────

const i18n = (max: number) => z.object({
  fi: z.string().trim().max(max).optional(), sv: z.string().trim().max(max).optional(), en: z.string().trim().max(max).optional(),
}).strict();

export const compositionSchema = z.array(z.object({
  component: z.enum(COMPONENTS),
  fibres: z.array(z.object({ fibre: z.enum(FIBRE_KEYS), percent: z.number().positive().max(100) }).strict()).min(1).max(10),
}).strict()).min(1).max(6);

const cm = z.number().positive().max(400);
const sizeChartSchema = z.array(z.object({
  size: z.string().trim().min(1).max(20),
  measuredOn: z.enum(["body", "garment"]),
  ...Object.fromEntries(MEASUREMENT_KEYS.map((k) => [k, cm.optional()])),
}).strict()).max(40);

const careSchema = z.object({
  wash: z.enum(["W95", "W60", "W40", "W40_MILD", "W30", "W30_MILD", "W30_VERY_MILD", "HAND", "NO_WASH"]).optional(),
  bleach: z.enum(["ANY", "OXYGEN_ONLY", "NO_BLEACH"]).optional(),
  tumble: z.enum(["NORMAL", "LOW", "NO_TUMBLE"]).optional(),
  naturalDry: z.enum(["LINE", "DRIP_LINE", "FLAT", "DRIP_FLAT", "LINE_SHADE", "FLAT_SHADE"]).optional(),
  iron: z.enum(["HIGH", "MEDIUM", "LOW", "NO_IRON"]).optional(),
  professional: z.enum(["P", "P_MILD", "F", "F_MILD", "NO_DRY_CLEAN", "W", "W_MILD", "W_VERY_MILD", "NO_WET_CLEAN"]).optional(),
}).strict();

function zodFor(a: AttrDef): z.ZodTypeAny {
  switch (a.kind) {
    case "enum": {
      const vals = a.values!;
      return typeof vals[0] === "number"
        ? z.number().refine((v) => vals.includes(v), { message: `Must be one of ${vals.join(", ")}` })
        : z.enum(vals as [string, ...string[]]);
    }
    case "enums": return z.array(z.enum(a.values as [string, ...string[]])).max(a.maxItems ?? a.values!.length).transform((v) => [...new Set(v)]);
    case "text": {
      let s = z.string().trim().max(a.max ?? 200);
      if (a.min) s = s.min(a.min);
      return a.key === "countryOfManufacture" || a.key === "countryOfOrigin" ? s.regex(/^[A-Za-z]{2}$/).transform((v) => v.toUpperCase()) : s;
    }
    case "int": return z.number().int().min(a.min ?? 0).max(a.max ?? 1_000_000);
    case "number": return z.number().min(a.min ?? 0).max(a.max ?? 1_000_000);
    case "bool": return z.boolean();
    case "i18n": return i18n(a.max ?? 2000);
    case "composition": return compositionSchema;
    case "sizeChart": return sizeChartSchema;
    case "care": return careSchema;
    case "dimensions": return z.object({ w: cm, h: cm, d: cm.optional() }).strict();
    case "month": return z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, "Use YYYY-MM");
    case "strings": return z.array(z.string().trim().min(1).max(a.max ?? 40)).max(a.maxItems ?? 10);
  }
}

const schemaCache = new Map<string, z.ZodTypeAny>();
export function attributesSchema(template: Template) {
  let s = schemaCache.get(template);
  if (!s) {
    // null clears a value
    s = z.object(Object.fromEntries(attrsFor(template).map((a) => [a.key, zodFor(a).nullable().optional()]))).strict();
    schemaCache.set(template, s);
  }
  return s;
}

/** Without a category only the common attributes are accepted (a draft can say the brand before it has a category). */
const commonSchema = z.object(Object.fromEntries(ATTRS.filter((a) => a.templates === "ALL").map((a) => [a.key, zodFor(a).nullable().optional()]))).strict();

export type FieldIssue = { field: string; code: string; message: L };

/** Validates attributes for a template; returns the clean object (nulls removed) or the field-level issues. */
export function validateAttributes(template: Template | null, raw: unknown): { ok: true; value: Record<string, unknown> } | { ok: false; issues: FieldIssue[] } {
  const schema = template ? attributesSchema(template) : commonSchema;
  const r = schema.safeParse(raw ?? {});
  if (!r.success) {
    const issues: FieldIssue[] = [];
    for (const i of r.error.issues) {
      if (i.code === "unrecognized_keys") {
        for (const k of i.keys) {
          issues.push({ field: `attributes.${k}`, code: "not_for_category", message: l(`"${k}" is not an attribute of this category`, `"${k}" ei ole tämän kategorian tieto`) });
        }
        continue;
      }
      const key = String(i.path[0] ?? "");
      const def = DEFS.get(key);
      const name = def?.label ?? l(key, key);
      issues.push({ field: `attributes.${i.path.join(".")}`, code: "invalid", message: l(`${name.en}: ${i.message}`, `${name.fi}: virheellinen arvo`) });
    }
    return { ok: false, issues };
  }
  const value = Object.fromEntries(Object.entries(r.data as Record<string, unknown>).filter(([, v]) => v !== null && v !== undefined));
  return { ok: true, value };
}

// ─── Facets ──────────────────────────────────────────────────────────────────

/** Facet keys that come from columns or options, not from attributes. */
const EXTRA_FACETS: Record<string, L> = {
  brand: l("Brand", "Merkki"),
  size: l("Size", "Koko"),
  fibre: l("Material (fibre)", "Materiaali (kuitu)"),
  shadeFamily: l("Shade family", "Sävyperhe"),
  undertone: l("Undertone", "Alasävy"),
  nickelFree: l("Nickel-free (verified)", "Nikkelitön (todennettu)"),
};
/** Columns and relations every category can filter on (handled in the search query itself). */
export const COLUMN_FILTERS: Record<string, L> = {
  condition: l("Condition", "Kunto"),
  audience: l("For", "Kenelle"),
  certificate: l("Certificates", "Sertifikaatit"),
};

export function facetKeysFor(template: Template): string[] {
  const keys = attrsFor(template).filter((a) => a.facet).map((a) => a.key);
  keys.push("brand");
  if (["APPAREL", "APPAREL_ACCESSORY", "FOOTWEAR", "JEWELLERY"].includes(template)) keys.push("size");
  if (["APPAREL", "APPAREL_ACCESSORY", "BAG", "ACCESSORY"].includes(template)) keys.push("fibre");
  if (template === "COSMETIC_MAKEUP" || template === "COSMETIC_NAIL") keys.push("shadeFamily", "undertone");
  if (template === "JEWELLERY") keys.push("nickelFree");
  return [...new Set(keys)];
}

export const ALL_FACET_KEYS = [...new Set(TEMPLATES.flatMap((t) => facetKeysFor(t)))];

export function facetLabel(key: string): L {
  return EXTRA_FACETS[key] ?? COLUMN_FILTERS[key] ?? DEFS.get(key)?.label ?? l(key, key);
}

type OptionRow = { size?: string | null; colourFamily?: string | null; shadeFamily?: string | null; undertone?: string | null; finish?: string | null };

/** The ProductFacet rows of a product: (key, value) pairs, values lower-case where they are free text. */
export function facetRows(template: Template | null, attrs: Record<string, any>, options: OptionRow[]): { key: string; value: string }[] {
  const out = new Map<string, { key: string; value: string }>();
  const add = (key: string, value: unknown) => {
    if (value === null || value === undefined || value === "") return;
    const v = String(value).trim().slice(0, 80);
    if (!v) return;
    const norm = key === "brand" || key === "size" ? v.toLowerCase() : v;
    out.set(`${key}|${norm}`, { key, value: norm });
  };
  if (attrs.brand) add("brand", attrs.brand);
  if (!template) return [...out.values()];
  const allowed = new Set(facetKeysFor(template));
  for (const a of attrsFor(template)) {
    if (!a.facet || !allowed.has(a.key)) continue;
    const v = attrs[a.key];
    if (Array.isArray(v)) v.forEach((x) => add(a.key, x));
    else if (typeof v === "boolean") { if (v) add(a.key, "true"); }
    else add(a.key, v);
  }
  if (allowed.has("fibre") && Array.isArray(attrs.fibreComposition)) {
    for (const c of attrs.fibreComposition) if (c.component === "main" || c.component === "outer") for (const f of c.fibres ?? []) add("fibre", f.fibre);
  }
  if (allowed.has("nickelFree") && ["nickel_free_material", "test_report_en1811"].includes(attrs.nickelBasis)) add("nickelFree", "true");
  for (const o of options) {
    if (allowed.has("size")) add("size", o.size);
    if (allowed.has("colourFamily")) add("colourFamily", o.colourFamily);
    if (allowed.has("shadeFamily")) add("shadeFamily", o.shadeFamily);
    if (allowed.has("undertone")) add("undertone", o.undertone);
    if (allowed.has("finish")) add("finish", o.finish);
  }
  return [...out.values()];
}

/** Composition as the label reads: "65 % puuvilla, 35 % polyesteri · Vuori: 100 % viskoosi" (descending, Art. 16). */
export function compositionText(comp: unknown, locale: "en" | "fi"): string | null {
  if (!Array.isArray(comp) || !comp.length) return null;
  const names: Record<string, L> = {
    main: l("", ""), outer: l("Outer", "Päällinen"), inner: l("Inner", "Sisäosa"), lining: l("Lining", "Vuori"),
    filling: l("Filling", "Täyte"), trim: l("Trim", "Somiste"), other: l("Other", "Muu"),
  };
  return comp.map((c: any) => {
    const fibres = [...(c.fibres ?? [])].sort((a: any, b: any) => b.percent - a.percent)
      .map((f: any) => `${String(f.percent).replace(".", locale === "fi" ? "," : ".")} % ${FIBRES[f.fibre]?.[locale] ?? f.fibre}`).join(", ");
    const n = names[c.component]?.[locale];
    return n ? `${n}: ${fibres}` : fibres;
  }).join(" · ");
}

/** Per component, the fibre percentages must add up to 100. */
export function compositionProblems(comp: unknown): FieldIssue[] {
  if (!Array.isArray(comp)) return [];
  const out: FieldIssue[] = [];
  comp.forEach((c: any, i: number) => {
    const sum = Math.round((c.fibres ?? []).reduce((s: number, f: any) => s + (Number(f.percent) || 0), 0) * 10) / 10;
    if (sum !== 100) {
      const s = String(sum).replace(".", ",");
      out.push({ field: `attributes.fibreComposition.${i}`, code: "composition_total", message: l(`Composition adds up to ${sum} %. It must total 100.`, `Koostumus on ${s} %. Prosenttien summan on oltava 100.`) });
    }
  });
  return out;
}

export { isCosmetic };
