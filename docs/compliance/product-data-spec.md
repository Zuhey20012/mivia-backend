# Malvoya product data spec (categories, attributes, filters, photos, editor)

Status: proposal for the next backend round, written 18 Oct 2026. Nothing here is built yet.
Companion document: `docs/compliance/apparel-beauty.md` (the law behind every REQUIRED-BY-LAW field; section numbers like "AB §3" point there).

How to read the attribute tables:

| Level | Meaning |
|---|---|
| **LAW** | Required by law for this kind of product (the product cannot be published without it, for business sellers). |
| **MALVOYA** | Required by Malvoya's own rules (needed for search, filters, safety checks or honest presentation). Publishing is blocked without it. |
| **OPTIONAL** | Shown when given; never blocks publishing. |
| **LAW\*** | Required by law, but the duty sits with the manufacturer or responsible person; Malvoya collects it so the listing can show it. For private sellers of second-hand goods it is "best effort" (see AB §7). |

Types: `text` (single line), `longtext`, `enum` (one value), `enum[]` (several), `int`, `decimal`, `bool`, `date`, `json`, `image[]`, `ref` (points to another record). Every user-facing value has an `en` and `fi` label; warnings and safety texts also take `sv` (see AB §1).

---

## 0. What exists today (read from the code, 18 Oct 2026)

| Where | What | Problem for this spec |
|---|---|---|
| `backend/prisma/schema.prisma` `Product` | `category String` (free text, "Dress", "Lipstick"…), `condition` enum NEW/LIKE_NEW/GOOD/FAIR/POOR, `tags String[]`, `gtin`, flags `isEcoFriendly`, `isHandmade`, `isSecondHand`, `isFeatured`, rental fields | No taxonomy, no attributes (fibres, ingredients, content, manufacturer…). `isEcoFriendly` is an unverified generic green claim (AB §5). |
| `ProductVariant` (the "options") | `size`, `color`, `sku`, `stock`, `priceAdjustCents` | No shade hex, no content/volume per option, so no unit price per option. |
| `Store` | `category StoreCategory` (APPAREL, COSMETICS, THRIFT, ACCESSORIES, HOME_DECOR, HANDMADE, **ECO_FRIENDLY**, OTHER), `isEcoFriendly`, `sellerType`, `businessId` | ECO_FRIENDLY and `isEcoFriendly` are generic green claims about a whole business (AB §5). |
| `backend/src/modules/products/products.schema.ts` | Search params `category`, `size`, `color`, `condition`, `secondHand`, **`eco`**, `handmade`, price, sort relevance/newest/price/rating | Category is matched by exact free text; no attribute filters. |
| `backend/src/modules/imports/mapping.ts` | `PRODUCT_CATEGORIES` = Clothing, Shoes, Bags, Accessories, Jewelry, Beauty, Home, Other; regex keyword mapping | Too coarse for beauty; "Other" is a dead end. |
| `malvoya_vendor/lib/screens/product_editor.dart` | Same 8 categories, fixed size list (XS–XXL, 36–45, One Size), 12 colours, switches Second hand / **Eco-friendly** / Handmade | No per-category template, no required legal fields. |
| `Malvoya_customer/lib/screens/home.dart` `_categories` | Hard-coded tiles: Clothing, Shoes, Bags, Accessories, Jewelry, Vintage, Beauty, **Home**, **Returns**; plus bento shelf tiles "Second Hand" and **"Eco-Friendly"** (leaf icon, mint/green) | "Home" (home décor) is outside the product scope; "Returns" is a service, not a category; "Eco-Friendly" is a generic claim. See §1.5. |
| `Malvoya_customer/lib/screens/catalogue.dart` | Filter chips: category, **Eco-friendly/Ekologinen**, sort, size (fixed list), price, Second hand, condition | No category-specific filters. |
| `Malvoya_customer/lib/screens/product_detail.dart` | Name, price, VAT note, chips (condition, Second hand, **Eco-friendly/Ympäristöystävällinen**, Handmade), description, a **generic hard-coded EU size table** for anything that looks like clothing, store card, seller info | No materials, ingredients, unit price, manufacturer/safety section, returns badge. The generic size table is not the shop's own chart, so it can mislead. |

---

## 1. Category taxonomy (drives the Home tab)

### 1.1 Recommendation: product type first, audience as a filter

**One structure: 10 top-level categories by product type, two levels deep, with audience (Women / Men / Kids / Unisex) as a switch and filter, not a top level.**

How the reference shops do it (patterns, observed from their public navigation; not copied):

| Shop | Top level | Why it matters to us |
|---|---|---|
| Zalando, Boozt | Audience first (Women / Men / Kids), then product type (Clothing, Shoes, Sports, Accessories, Beauty) | Works for very large fashion catalogues where every audience has thousands of items. Beauty sits inside "Women" as a sub-shop. |
| Sephora, Lyko | Product type first (Makeup, Skincare, Hair, Fragrance, Body, Men…), audience only as a facet or a small "Men" entry | Beauty is mostly not gendered; shoppers think in product types ("I need a serum"). |

Why product type first fits Malvoya:
1. **Mixed apparel + beauty.** Audience-first hides beauty under "Women" and leaves men's and unisex beauty nowhere. Product-type-first treats Makeup, Skincare, Haircare and Fragrance as equals of Clothing and Shoes, the way Sephora and Lyko do.
2. **Thin local inventory.** Malvoya shows what shops near the customer have. Audience × type (e.g. Men › Earrings) splits a small catalogue into many near-empty pages. One level of product type plus an audience switch keeps pages full.
3. **Legal templates follow product type, not audience.** Textile, footwear, cosmetics and jewellery rules (AB §1–§9) attach to the subcategory, so the taxonomy doubles as the attribute-template switch.
4. **Kids still gets special handling:** choosing audience *Kids* or *Baby* adds the children's-safety fields (AB §8) to the template.

The audience switch sits at the top of Home as a segmented control: **Kaikki / Naiset / Miehet / Lapset** (All / Women / Men / Kids). It filters the tiles' counts and every catalogue opened from Home. Unisex products appear under both Women and Men. Beauty products default to Unisex.

"Second-hand & vintage" is the 10th tile because Finnish shoppers look for it as a destination (Zalando Pre-owned, Sellpy, Emmy). It is a **collection** (a saved filter `isSecondHand=true`), not a separate product type: every second-hand item still has a real subcategory (e.g. `clothing-dresses`).

### 1.2 Rules for slugs and display

- Slugs are lowercase kebab-case English, stable forever: never rename a slug, only its display names. Top level: `clothing`. Subcategory: `clothing-dresses`.
- A product has exactly one subcategory slug (`Product.categorySlug`). The top level is derived from it.
- `productType` (e.g. lipstick, ankle boot) is an attribute inside the subcategory, used as a filter chip. It is the third level for shoppers who want it, without a third navigation level.
- The API serves the tree from one place (`GET /categories?audience=&lat=&lng=` → `[{slug, name{en,fi}, icon, tile, count, children[...] }]`) and returns only nodes with in-stock products near the delivery location, so Home never shows an empty tile. The apps stop hard-coding category lists (today they are duplicated in `home.dart`, `catalogue.dart`, `product_editor.dart` and `imports/mapping.ts`).
- Icons are Material icon names (Flutter `Icons.*`, outlined/rounded variants as the app already uses). They are suggestions; check each in the Material Symbols catalogue before use. Avoid `Icons.eco` and leaf/green-planet icons anywhere (AB §5: images and colours can make a generic green claim).
- Tile colours come from the Birch palette in `Malvoya_customer/lib/config/theme.dart`: `lilac #F1E7F6`, `clay #E9DFD2`, `mint #E3F2E9`, `sunshineLight #FDF1D8`, `peach #FBEAE6`, `sand #F3EEE6`, with the ink colours the app already pairs with them (`primary`, `clayInk`, `moss`, `#8A5A00`, `lingon`, `inkSecondary`). Dark mode uses `AppTheme.pastel()` as today. Mint is used for ordinary categories (e.g. bags), never to signal "green".

Attribute templates (defined in §2): `APPAREL`, `APPAREL_ACCESSORY`, `FOOTWEAR`, `BAG`, `ACCESSORY`, `EYEWEAR`, `WATCH`, `JEWELLERY`, `COSMETIC_MAKEUP`, `COSMETIC_SKIN`, `COSMETIC_HAIR`, `COSMETIC_NAIL`, `FRAGRANCE`, `BEAUTY_TOOL`. Every template also includes `COMMON` (§2.1). Audience Kids/Baby adds `KIDS_SAFETY` (§2.11).

### 1.3 The tree (order = Home order, as a Finnish shopper expects)

#### 1. `clothing` — Vaatteet / Clothing — `checkroom` — lilac

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `clothing-dresses` | Mekot | Dresses | `checkroom` | lilac | APPAREL |
| `clothing-tops` | Paidat ja topit | T-shirts & tops | `checkroom` | lilac | APPAREL |
| `clothing-shirts-blouses` | Kauluspaidat ja puserot | Shirts & blouses | `dry_cleaning` | lilac | APPAREL |
| `clothing-knitwear` | Neuleet ja hupparit | Knitwear & hoodies | `checkroom` | clay | APPAREL |
| `clothing-jackets-coats` | Takit | Jackets & coats | `dry_cleaning` | clay | APPAREL |
| `clothing-trousers-jeans` | Housut ja farkut | Trousers & jeans | `checkroom` | sand | APPAREL |
| `clothing-skirts-shorts` | Hameet ja shortsit | Skirts & shorts | `checkroom` | peach | APPAREL |
| `clothing-suits-blazers` | Puvut ja bleiserit | Suits & blazers | `dry_cleaning` | sand | APPAREL |
| `clothing-sportswear` | Urheiluvaatteet | Sportswear | `directions_run` | mint | APPAREL |
| `clothing-underwear-nightwear` | Alusvaatteet, sukat ja yöasut | Underwear, socks & nightwear | `nightlight` | peach | APPAREL |
| `clothing-swimwear` | Uima-asut | Swimwear | `pool` | mint | APPAREL |
| `clothing-other` | Muut vaatteet | Other clothing | `checkroom` | sand | APPAREL |

#### 2. `shoes` — Kengät / Shoes — `snowshoeing` (as today; consider `steps` in Material Symbols) — clay

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `shoes-sneakers` | Tennarit | Sneakers | `directions_run` | clay | FOOTWEAR |
| `shoes-boots` | Saappaat ja nilkkurit | Boots & ankle boots | `snowshoeing` | clay | FOOTWEAR |
| `shoes-winter-rubber-boots` | Talvi- ja kumisaappaat | Winter & rubber boots | `ac_unit` | sand | FOOTWEAR |
| `shoes-heels` | Korkokengät | Heels | `snowshoeing` | lilac | FOOTWEAR |
| `shoes-flats-loafers` | Ballerinat ja loaferit | Flats & loafers | `snowshoeing` | peach | FOOTWEAR |
| `shoes-sandals` | Sandaalit ja varvastossut | Sandals & slides | `beach_access` | sunshineLight | FOOTWEAR |
| `shoes-sports-outdoor` | Urheilu- ja ulkoilukengät | Sports & outdoor shoes | `hiking` | mint | FOOTWEAR |
| `shoes-slippers` | Tohvelit ja sisäkengät | Slippers & indoor shoes | `weekend` | sand | FOOTWEAR |

#### 3. `bags` — Laukut / Bags — `shopping_bag` — mint

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `bags-handbags` | Käsilaukut | Handbags | `shopping_bag` | mint | BAG |
| `bags-shoulder-crossbody` | Olka- ja crossbody-laukut | Shoulder & crossbody bags | `shopping_bag` | mint | BAG |
| `bags-totes` | Kangas- ja ostoskassit | Totes & shoppers | `local_mall` | sand | BAG |
| `bags-backpacks` | Reput | Backpacks | `backpack` | clay | BAG |
| `bags-clutches` | Pikkulaukut ja clutchit | Clutches & evening bags | `shopping_bag` | lilac | BAG |
| `bags-wallets` | Lompakot ja korttikotelot | Wallets & card holders | `account_balance_wallet` | sand | BAG |
| `bags-travel` | Matka- ja viikonloppulaukut | Travel & weekend bags | `luggage` | clay | BAG |
| `bags-belt-bags` | Vyölaukut | Belt bags | `shopping_bag` | peach | BAG |

#### 4. `accessories` — Asusteet / Accessories — `watch` — sunshineLight

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `accessories-hats-beanies` | Pipot ja hatut | Beanies & hats | `face` | sunshineLight | APPAREL_ACCESSORY |
| `accessories-scarves` | Huivit | Scarves & shawls | `waves` | peach | APPAREL_ACCESSORY |
| `accessories-gloves-mittens` | Käsineet ja lapaset | Gloves & mittens | `back_hand` | sand | APPAREL_ACCESSORY |
| `accessories-belts` | Vyöt | Belts | `straighten` | clay | ACCESSORY |
| `accessories-sunglasses` | Aurinkolasit | Sunglasses | `visibility` | sunshineLight | EYEWEAR |
| `accessories-watches` | Kellot | Watches | `watch` | lilac | WATCH |
| `accessories-hair` | Hiusasusteet | Hair accessories | `content_cut` | peach | ACCESSORY |
| `accessories-small` | Solmiot ja muut asusteet | Ties & small accessories | `style` | sand | ACCESSORY |

#### 5. `jewellery` — Korut / Jewellery — `diamond` — lilac

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `jewellery-earrings` | Korvakorut | Earrings | `hearing` | lilac | JEWELLERY |
| `jewellery-necklaces` | Kaulakorut ja riipukset | Necklaces & pendants | `diamond` | lilac | JEWELLERY |
| `jewellery-rings` | Sormukset | Rings | `radio_button_unchecked` | sunshineLight | JEWELLERY |
| `jewellery-bracelets` | Rannekorut | Bracelets & bangles | `diamond` | peach | JEWELLERY |
| `jewellery-piercing` | Lävistyskorut | Piercing jewellery | `diamond` | sand | JEWELLERY |
| `jewellery-brooches` | Rintaneulat | Brooches & pins | `push_pin` | clay | JEWELLERY |
| `jewellery-sets-charms` | Korusetit ja hely | Jewellery sets & charms | `auto_awesome` | lilac | JEWELLERY |

#### 6. `makeup` — Meikit / Makeup — `brush` — peach

| Slug | FI | EN | Icon | Tile | Template | productType values (filter chips) |
|---|---|---|---|---|---|---|
| `makeup-face` | Kasvot | Face | `face_retouching_natural` | peach | COSMETIC_MAKEUP | foundation, concealer, powder, blush, bronzer, highlighter, primer, setting_spray, bb_cc_cream |
| `makeup-eyes` | Silmät | Eyes | `visibility` | lilac | COSMETIC_MAKEUP | mascara, eyeliner, eyeshadow, eyeshadow_palette, brow, lash_serum, false_lashes (not a cosmetic: BEAUTY_TOOL) |
| `makeup-lips` | Huulet | Lips | `brush` | peach | COSMETIC_MAKEUP | lipstick, liquid_lipstick, lip_gloss, lip_liner, tinted_lip_balm |
| `makeup-nails` | Kynnet | Nails | `back_hand` | sunshineLight | COSMETIC_NAIL | nail_polish, gel_polish, top_base_coat, nail_care, nail_polish_remover |
| `makeup-tools` | Siveltimet ja välineet | Brushes & tools | `brush` | sand | BEAUTY_TOOL | brush, sponge, eyelash_curler, mirror, bag |
| `makeup-sets` | Meikkisetit ja paletit | Sets & palettes | `palette` | clay | COSMETIC_MAKEUP | set, palette |

#### 7. `skincare` — Ihonhoito / Skincare — `spa` — mint

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `skincare-cleansers` | Puhdistus ja meikinpoisto | Cleansers & makeup removers | `water_drop` | mint | COSMETIC_SKIN |
| `skincare-toners-mists` | Kasvovedet ja suihkeet | Toners & mists | `water_drop` | sand | COSMETIC_SKIN |
| `skincare-serums` | Seerumit ja tehohoidot | Serums & treatments | `science` | lilac | COSMETIC_SKIN |
| `skincare-moisturisers` | Kosteusvoiteet | Moisturisers | `spa` | mint | COSMETIC_SKIN |
| `skincare-eye` | Silmänympärysvoiteet | Eye care | `visibility` | peach | COSMETIC_SKIN |
| `skincare-masks-exfoliators` | Naamiot ja kuorinnat | Masks & exfoliators | `face` | clay | COSMETIC_SKIN |
| `skincare-sun-selftan` | Aurinkosuojat ja itseruskettavat | Sun care & self-tan | `wb_sunny` | sunshineLight | COSMETIC_SKIN |
| `skincare-body` | Vartalonhoito ja deodorantit | Body care & deodorants | `shower` | mint | COSMETIC_SKIN |
| `skincare-hands-feet` | Käsien ja jalkojen hoito | Hand & foot care | `back_hand` | sand | COSMETIC_SKIN |

#### 8. `haircare` — Hiustenhoito / Haircare — `content_cut` — sunshineLight

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `haircare-shampoo` | Shampoot | Shampoo | `water_drop` | sunshineLight | COSMETIC_HAIR |
| `haircare-conditioner` | Hoitoaineet | Conditioner | `water_drop` | peach | COSMETIC_HAIR |
| `haircare-masks-treatments` | Hiusnaamiot ja tehohoidot | Masks & treatments | `spa` | lilac | COSMETIC_HAIR |
| `haircare-oils-serums` | Hiusöljyt ja seerumit | Oils & serums | `opacity` | sunshineLight | COSMETIC_HAIR |
| `haircare-styling` | Muotoilutuotteet | Styling | `air` | mint | COSMETIC_HAIR |
| `haircare-colour` | Hiusvärit | Hair colour | `palette` | clay | COSMETIC_HAIR |
| `haircare-scalp` | Hiuspohjan hoito | Scalp care | `spa` | sand | COSMETIC_HAIR |
| `haircare-brushes-tools` | Harjat ja välineet | Brushes & tools | `brush` | sand | BEAUTY_TOOL |

Electrical hair tools (dryers, straighteners, curlers) are **not** in the tree for now: they bring electrical-safety, CE, WEEE and battery producer duties that the templates here do not cover. Add them later with their own template.

#### 9. `fragrance` — Tuoksut / Fragrance — `local_florist` — peach

| Slug | FI | EN | Icon | Tile | Template |
|---|---|---|---|---|---|
| `fragrance-parfum-edp` | Parfyymit ja eau de parfumit | Parfum & eau de parfum | `local_florist` | peach | FRAGRANCE |
| `fragrance-edt-cologne` | Eau de toiletteet ja colognet | Eau de toilette & cologne | `local_florist` | lilac | FRAGRANCE |
| `fragrance-body-hair-mists` | Vartalo- ja hiussuihkeet | Body & hair mists | `air` | mint | FRAGRANCE |
| `fragrance-oils-solid` | Tuoksuöljyt ja kiinteät tuoksut | Perfume oils & solid perfume | `opacity` | sand | FRAGRANCE |
| `fragrance-gift-sets` | Tuoksulahjapakkaukset | Gift sets | `redeem` | clay | FRAGRANCE |
| `fragrance-travel` | Matkakoot | Travel sizes | `luggage` | sunshineLight | FRAGRANCE |

Home fragrance (candles, diffusers) is not in scope (different rules: candle fire safety, CLP chemical labelling).

#### 10. `second-hand` — Käytetty ja vintage / Second-hand & vintage — `recycling` (as today) — sunshine badge on a sand tile

A collection: each child is a saved filter `isSecondHand=true` plus a top level. No product is filed here directly.

| Slug | FI | EN | Filter | Icon | Tile |
|---|---|---|---|---|---|
| `second-hand-clothing` | Käytetyt vaatteet | Second-hand clothing | top = clothing | `checkroom` | sand |
| `second-hand-shoes` | Käytetyt kengät | Second-hand shoes | top = shoes | `snowshoeing` | clay |
| `second-hand-bags` | Käytetyt laukut | Second-hand bags | top = bags | `shopping_bag` | mint |
| `second-hand-accessories` | Käytetyt asusteet | Second-hand accessories | top = accessories | `watch` | sunshineLight |
| `second-hand-jewellery` | Käytetyt korut | Second-hand jewellery | top = jewellery | `diamond` | lilac |
| `second-hand-designer` | Merkkituotteet | Designer & luxury | `brandTier = designer` (and authenticity checked, §2.13) | `auto_awesome` | peach |
| `second-hand-vintage` | Vintage | Vintage | `vintage = true` (made 20+ years ago, seller's statement) | `history` | clay |
| `second-hand-kids` | Käytetyt lastenvaatteet | Second-hand kids' clothes | audience = kids/baby | `child_care` | sand |

Second-hand cosmetics and fragrance are not offered (Malvoya rule, see AB §3.7): only sealed, unused, in-date beauty products may be listed, and only by business sellers at launch.

### 1.4 Mapping free-text and imported categories to slugs

The importers (`backend/src/modules/imports/{shopify,woocommerce,csv}.ts`) and the existing free-text `Product.category` values map onto slugs with one shared function, replacing `mapCategory()` in `mapping.ts`.

**Inputs, in priority order** (first confident hit wins):
1. CSV `category` column, exact: a slug (`clothing-dresses`), or a path in either language (`Clothing > Dresses`, `Vaatteet > Mekot`), or an exact FI/EN subcategory name. New CSV column `category_slug` is preferred and documented in the CSV template.
2. WooCommerce `categories[].name` (often hierarchical, e.g. "Naiset", "Mekot"): match each name; the deepest match wins; audience words become `audience`.
3. Shopify `product_type`, then `tags`, then `title`.
4. Free-text `Product.category` of existing rows (one-off migration).
5. Product name and description (lowest confidence).

**Matching rules**
- Lowercase, strip accents only for comparison of ASCII-typed Finnish (`kengat` = `kengät`), collapse spaces and punctuation.
- Finnish compounds put the head noun last (`iltamekko`, `talvitakki`, `kumisaappaat`), so Finnish keywords match **as suffixes or whole words**, English keywords as whole words (plural optional).
- Longest keyword wins; ties go to the more specific subcategory (subcategory keyword beats top-level keyword).
- Words that set **audience**, not category: FI `naiset, naisten, nais-, miehet, miesten, mies-, lapset, lasten, junior, vauva, vauvan, tytöt, tyttöjen, pojat, poikien, unisex`; EN `women, womens, ladies, woman, men, mens, man, kids, children, child, baby, girls, boys, junior, unisex`; SV (common in Finnish shops) `dam, herr, barn`.
- Words that set **second-hand**, not category: `käytetty, kierrätetty (as a condition), vintage, second hand, secondhand, pre-owned, preloved, used, retro` → `isSecondHand=true` (vintage also sets `vintage=true` for review). Existing `USED_TAG` regex stays.
- If only a top level matches, file under its `*-other` or the most common child and flag "check category" in the import report. If nothing matches, the draft gets **no** category and cannot be published until the store picks one. Never default to "Other".
- Words that indicate **out-of-scope or restricted** goods put the draft on hold with a message, not a category: candles/kynttilä, diffuser, sisustus, home décor, food supplement/ravintolisä/vitamiini/kollageeni (Ruokavirasto area), "lääke", medicine, hand sanitiser/käsidesi (biocide), electric/sähkö + hair dryer/hiustenkuivaaja/suoristusrauta, nail glue/kynsiliima (CLP chemical), tattoo ink/tatuointiväri.

**Keyword lists** (FI | EN). The list is a starting point; keep it in one data file with tests.

| Slug | FI keywords | EN keywords |
|---|---|---|
| `clothing-dresses` | mekko, leninki, tunikamekko | dress, gown, sundress |
| `clothing-tops` | t-paita, paita, toppi, top, body, pitkähihainen | t-shirt, tee, tshirt, top, tank, camisole, bodysuit, longsleeve |
| `clothing-shirts-blouses` | kauluspaita, pusero, paitapusero | shirt, blouse, button-down |
| `clothing-knitwear` | neule, villapaita, neuletakki, huppari, college, collegepaita, svetari | sweater, jumper, knit, cardigan, hoodie, sweatshirt, pullover |
| `clothing-jackets-coats` | takki, jakku (ei puvun), toppatakki, untuvatakki, parka, kuoritakki, liivi | jacket, coat, parka, puffer, down jacket, gilet, vest, windbreaker, raincoat |
| `clothing-trousers-jeans` | housut, farkut, legginsit, chinot, verkkarit, collegehousut | trousers, pants, jeans, denim, leggings, chinos, joggers |
| `clothing-skirts-shorts` | hame, shortsit, sortsit | skirt, shorts |
| `clothing-suits-blazers` | puku, bleiseri, pikkutakki, smokki, haalari (juhla) | suit, blazer, tuxedo |
| `clothing-sportswear` | urheiluvaate, treeni-, juoksu-, sport-, urheilurintaliivit | sportswear, activewear, training, running, gym, sports bra |
| `clothing-underwear-nightwear` | alusvaate, alushousut, rintaliivit, bokserit, sukat, sukkahousut, yöpaita, pyjama, aamutakki | underwear, briefs, boxers, bra, lingerie, socks, tights, pyjamas, nightwear, robe, loungewear |
| `clothing-swimwear` | uimapuku, bikinit, uimahousut, uima-asu | swimsuit, swimwear, bikini, swim shorts, trunks |
| `shoes-sneakers` | tennarit, tennari, lenkkarit, sneakerit | sneakers, trainers, sneaker |
| `shoes-boots` | saappaat, nilkkurit, maiharit, chelsea | boots, ankle boots, chelsea boots |
| `shoes-winter-rubber-boots` | talvikengät, talvisaappaat, kumisaappaat, toppakengät | winter boots, snow boots, rain boots, rubber boots, wellies |
| `shoes-heels` | korkokengät, avokkaat, piikkikorot | heels, pumps, stilettos |
| `shoes-flats-loafers` | ballerinat, loaferit, mokkasiinit, juhlakengät (matala) | flats, ballet flats, loafers, moccasins, brogues |
| `shoes-sandals` | sandaalit, varvastossut, sandaletit, puukengät | sandals, slides, flip-flops, clogs, mules |
| `shoes-sports-outdoor` | juoksukengät, ulkoilukengät, vaelluskengät, urheilukengät | running shoes, hiking shoes, trail shoes, sports shoes |
| `shoes-slippers` | tohvelit, sisäkengät, aamutossut | slippers, house shoes |
| `bags-handbags` | käsilaukku | handbag, purse |
| `bags-shoulder-crossbody` | olkalaukku, olkalaukut, crossbody | shoulder bag, crossbody, messenger |
| `bags-totes` | kangaskassi, kassi, ostoskassi, shopperi | tote, shopper, canvas bag |
| `bags-backpacks` | reppu, selkäreppu | backpack, rucksack |
| `bags-clutches` | pikkulaukku, iltalaukku, clutch | clutch, evening bag |
| `bags-wallets` | lompakko, kukkaro, korttikotelo | wallet, purse (small), card holder, coin purse |
| `bags-travel` | matkalaukku, weekend-laukku, urheilukassi | travel bag, weekender, duffel, suitcase |
| `bags-belt-bags` | vyölaukku | belt bag, bum bag, fanny pack |
| `accessories-hats-beanies` | pipo, hattu, lippis, lippalakki, myssy | beanie, hat, cap, bucket hat |
| `accessories-scarves` | huivi, kaulahuivi, kaulaliina, tuubihuivi | scarf, shawl, snood |
| `accessories-gloves-mittens` | käsineet, hanskat, lapaset, sormikkaat | gloves, mittens |
| `accessories-belts` | vyö | belt |
| `accessories-sunglasses` | aurinkolasit | sunglasses, shades |
| `accessories-watches` | kello, rannekello | watch, wristwatch |
| `accessories-hair` | hiuspinni, panta, scrunchie, hiussolki, hiuskoru | hair clip, headband, scrunchie, hair tie, barrette |
| `accessories-small` | solmio, rusetti, taskuliina, avaimenperä | tie, bow tie, pocket square, keyring |
| `jewellery-earrings` | korvakorut, korvakoru, nappikorvikset, renkaat (korva) | earrings, studs, hoops |
| `jewellery-necklaces` | kaulakoru, riipus, ketju | necklace, pendant, chain, choker |
| `jewellery-rings` | sormus | ring |
| `jewellery-bracelets` | rannekoru, rannerengas, ranneketju | bracelet, bangle, cuff |
| `jewellery-piercing` | lävistyskoru, nenäkoru, napakoru | piercing, nose ring, belly ring, body jewellery |
| `jewellery-brooches` | rintaneula, rintakoru | brooch, pin |
| `jewellery-sets-charms` | korusetti, hela, berloki | jewellery set, charm |
| `makeup-face` | meikkivoide, peitevoide, puuteri, poskipuna, aurinkopuuteri, korostus, pohjustusvoide | foundation, concealer, powder, blush, bronzer, highlighter, primer, bb cream, cc cream |
| `makeup-eyes` | ripsiväri, silmänrajaus, rajauskynä, luomiväri, kulmakynä, kulmageeli | mascara, eyeliner, eyeshadow, brow pencil, brow gel |
| `makeup-lips` | huulipuna, huulikiilto, huultenrajauskynä, sävyttävä huulivoide | lipstick, lip gloss, lip liner, lip tint |
| `makeup-nails` | kynsilakka, geelilakka, aluslakka, päällyslakka, kynsilakanpoistoaine | nail polish, gel polish, base coat, top coat, nail polish remover |
| `makeup-tools` | sivellin, meikkisieni, ripsitaivutin | brush, makeup sponge, eyelash curler |
| `makeup-sets` | meikkisetti, paletti | makeup set, palette |
| `skincare-cleansers` | puhdistusaine, puhdistusgeeli, meikinpoistoaine, misellivesi, puhdistusöljy | cleanser, face wash, makeup remover, micellar water, cleansing oil |
| `skincare-toners-mists` | kasvovesi, kasvosuihke, esanssi | toner, face mist, essence |
| `skincare-serums` | seerumi, tehohoito, ampulli | serum, treatment, ampoule |
| `skincare-moisturisers` | kosteusvoide, päivävoide, yövoide, kasvovoide | moisturiser, moisturizer, day cream, night cream, face cream |
| `skincare-eye` | silmänympärysvoide, silmävoide | eye cream, eye serum |
| `skincare-masks-exfoliators` | kasvonaamio, naamio, kuorinta, kuorinta-aine | face mask, sheet mask, exfoliator, scrub, peel |
| `skincare-sun-selftan` | aurinkosuoja, aurinkovoide, itseruskettava | sunscreen, spf, sun cream, self-tan, after sun |
| `skincare-body` | vartalovoide, suihkusaippua, suihkugeeli, deodorantti, vartaloöljy, kylpy- | body lotion, body cream, shower gel, body wash, deodorant, body oil, bath |
| `skincare-hands-feet` | käsivoide, jalkavoide | hand cream, foot cream |
| `haircare-shampoo` | shampoo, kuivashampoo | shampoo, dry shampoo |
| `haircare-conditioner` | hoitoaine, hoitosuihke | conditioner, leave-in |
| `haircare-masks-treatments` | hiusnaamio, tehohoito (hius) | hair mask, hair treatment |
| `haircare-oils-serums` | hiusöljy, hiusseerumi | hair oil, hair serum |
| `haircare-styling` | muotoilutuote, hiuslakka, vaha, geeli, muotovaahto, lämpösuoja | styling, hairspray, wax, gel, mousse, heat protectant |
| `haircare-colour` | hiusväri, sävyte, hennaväri | hair dye, hair colour, hair color, toner (hair), henna |
| `haircare-scalp` | hiuspohja, hilseshampoo (watch claims) | scalp, scalp serum |
| `haircare-brushes-tools` | hiusharja, kampa | hairbrush, comb |
| `fragrance-parfum-edp` | hajuvesi, parfyymi, eau de parfum, edp | perfume, parfum, eau de parfum, edp |
| `fragrance-edt-cologne` | eau de toilette, edt, cologne, partavesi | eau de toilette, edt, cologne, aftershave |
| `fragrance-body-hair-mists` | vartalosuihke, hiustuoksu | body mist, hair mist |
| `fragrance-oils-solid` | tuoksuöljy, kiinteä hajuvesi | perfume oil, solid perfume |
| `fragrance-gift-sets` | tuoksulahjapakkaus | fragrance gift set |
| `fragrance-travel` | matkakoko, minikoko | travel size, mini, travel spray |

Shopify and WooCommerce attribute names that map to **option dimensions** (extends `SIZE_OPTION`/`COLOR_OPTION` in the importers): size/koko/storlek → `size`; color/colour/väri/färg → `colour`; shade/sävy/nyans → `shade`; volume/size (when values end in ml/g)/tilavuus/koko (ml) → `content`. A beauty product whose "Size" values look like `30 ml` gets `content`, not `size`.

### 1.5 Today's hard-coded Home tiles, and StoreCategory

| Today | Recommendation |
|---|---|
| Home tile **"Home" (Koti & Sisustus)** | Remove from Home and from the store editor's category list for new products. Home décor is outside the product scope (apparel, footwear, accessories, jewellery, beauty, fragrance). Existing products in "Home": move to hidden "needs category" and ask the store; home textiles (e.g. a scarf filed as Home) map to their real category. If the owner later wants home textiles, add a separate top level with its own template (textile labelling applies). |
| Home tile **"Returns" (Palautus)** | Remove from the category grid: it is a service, not a category, and a tile among categories hurts findability for both. Returns already open from the Orders tab (`orders.dart`) and from each order (`order_detail.dart`); keep those, and add "Palautukset / Returns" to the Profile menu. |
| Home tile **"Vintage"** and shelf tile **"Second Hand"** | Merge into the single 10th tile `second-hand` (Käytetty ja vintage), with `second-hand-vintage` as a child. |
| Shelf tile **"Eco-Friendly"** (leaf icon, green), category "Ekoystävällinen" in `l10n.dart`, `CategoryDetailScreen` case `Eco-Friendly`, catalogue chip "Ekologinen", product chip "Ympäristöystävällinen" | Remove (AB §5: a generic environmental claim, banned since 27 Sept 2026 without recognised excellent environmental performance). Replace the shelf tile with a real collection when it has stock, e.g. "Valmistettu Suomessa / Made in Finland" (origin fact) or "Sertifioidut tuotteet / Certified products" (shows only items with a verified certificate, each chip naming its scheme). |
| `StoreCategory` enum incl. **ECO_FRIENDLY** (`store_setup.dart` label "Eco-friendly / Ekologinen", admin `Vendors.tsx` green badge) and `Store.isEcoFriendly` | Drop ECO_FRIENDLY now (a generic green claim about a whole business, AB §5 points 4a/4b). Migrate those stores to `OTHER` and ask them to pick. Longer term replace the single `StoreCategory` with what the store actually sells, derived from its products' top-level slugs (shown as "Myy: Vaatteet, Korut"), plus factual store attributes: `sellsSecondHand`, `makesOwnProducts` (handmade/own brand, which also makes the store the GPSR manufacturer), `sellerType`. HOME_DECOR: drop for new stores. THRIFT → `sellsSecondHand=true`. HANDMADE → `makesOwnProducts=true`. |

---

## 2. Attributes per template

### 2.1 COMMON (every product)

| Key | EN label | FI label | Type | Allowed values / format | Level | Notes |
|---|---|---|---|---|---|---|
| `categorySlug` | Category | Kategoria | enum | a subcategory slug from §1.3 | MALVOYA | Replaces free-text `category`. |
| `audience` | For | Kenelle | enum[] | women, men, unisex, kids, baby | MALVOYA (apparel, shoes, accessories, jewellery); OPTIONAL (beauty, default unisex) | kids/baby adds KIDS_SAFETY. |
| `brand` | Brand | Merkki | text ≤ 60 | free text with autocomplete from known brands; "No brand / Merkitön" allowed | MALVOYA | Needed for counterfeit checks and Safety Gate matching. |
| `name`, `description` | Name, Description | Nimi, Kuvaus | text, longtext | as today | MALVOYA / OPTIONAL | Claims linter runs on both (§2.14). |
| `productModel` | Model / type | Malli / tyyppi | text ≤ 80 | model name or number from the label | LAW\* (GPSR Art. 19(c)) | "Type" in GPSR terms. |
| `gtin` | EAN / GTIN | EAN-koodi | text | 8, 12, 13 or 14 digits with valid check digit (`validGtin` exists) | OPTIONAL (strongly encouraged) | Best key for recalls and Safety Gate matching. Per option where options differ. |
| `batchOrSerial` | Batch / serial | Erä / sarjanumero | text | free | OPTIONAL on the listing; LAW for cosmetics on the pack | Shown when the shop sells a specific batch (useful for recalls). |
| `manufacturer` | Manufacturer | Valmistaja | ref → `EconomicOperator` | `{name, postalAddress, email or contactUrl, countryCode}` | LAW\* (GPSR Art. 19(a)) | Reusable records per store ("Add manufacturer once, pick it next time"). Prefilled from the store when `makesOwnProducts`. |
| `euResponsiblePerson` | EU responsible person | Vastuuhenkilö EU:ssa | ref → `EconomicOperator` | same shape, EU/EEA country | LAW\* when the manufacturer is outside the EU (GPSR Art. 19(b), Art. 16) | Editor shows it only when manufacturer country is not EU/EEA. For cosmetics this is usually the same as the Cosmetics Regulation responsible person (§2.7). |
| `warnings` | Warnings and safety information | Varoitukset ja turvallisuustiedot | json `{fi, sv, en?}` longtext | text as on the label | LAW\* where the product carries warnings (GPSR Art. 19(d)) | FI and SV required when present on the product (Tukes: Finnish and Swedish). "No warnings on the label" is an explicit choice, not a blank. |
| `safetyImages` | Label and safety photos | Pakkausmerkintä- ja turvallisuuskuvat | image[] ≤ 6 | photos of label, warning panel, instructions | OPTIONAL (MALVOYA for cosmetics: ingredient panel photo) | Supplements, never replaces, the typed text (text must be searchable and accessible). |
| `countryOfManufacture` | Made in | Valmistusmaa | enum | ISO 3166-1 alpha-2 | OPTIONAL (LAW for imported cosmetics: country of origin on label) | "Made in Finland" filter uses FI. Must be truthful; evidence on request. |
| `certifications` | Certificates | Sertifikaatit | ref[] → `ProductCertification` | see §2.12 | OPTIONAL | Replaces `isEcoFriendly`. |
| `condition` | Condition | Kunto | enum | NEW, LIKE_NEW, GOOD, FAIR (POOR kept for legacy, shown as "Worn / Kulunut", defects note required) | MALVOYA | See §2.13. |
| `isSecondHand` | Second-hand | Käytetty | bool | | MALVOYA | Must be true when condition ≠ NEW for apparel/shoes/bags/accessories/jewellery; never true for beauty. |
| `isHandmade` | Handmade | Käsintehty | bool | | OPTIONAL | Factual; the shop is then the manufacturer. |
| `hygieneSeal` | Hygiene seal | Hygieniasinetti | bool | | MALVOYA (auto-on for COSMETIC_*, FRAGRANCE, `jewellery-piercing`; store may turn on for earrings in sealed packs) | Drives the returns badge (AB §6). Snapshot onto `OrderItem` at purchase. |
| `hygieneSealDescription` | What the seal is | Sinetin kuvaus | enum | shrink_wrap, sealed_cap_or_foil, sealed_box, sealed_pouch | MALVOYA when `hygieneSeal` | Shown in the badge text ("sealed foil under the cap"). |
| `images` | Photos | Kuvat | image[] | minimum set per template (§4) | MALVOYA | Upload rules as today. |
| `safetySelfCertification` | (store level) I only offer products that comply with EU law | Tarjoan vain EU-lainsäädännön mukaisia tuotteita | bool + timestamp | | LAW (GPSR Art. 22(10)(b)) | Taken once at onboarding, stored per store with terms version. |

`EconomicOperator` (new table, per store, reusable): `id, storeId, role (manufacturer | importer | authorised_rep | fulfilment_provider | cosmetics_rp), name, postalAddress (line, postcode, city, countryCode), email, contactUrl, phone?`. One record can serve as both GPSR manufacturer and cosmetics responsible person.

### 2.2 APPAREL (all `clothing-*`)

| Key | EN | FI | Type | Allowed values | Level | Notes |
|---|---|---|---|---|---|---|
| `fibreComposition` | Material | Materiaali | json | `[{component: main/lining/filling/trim/..., fibres: [{fibre, percent}]}]`; percents per component sum to 100; fibre from the Annex I list below | LAW (Reg. 1007/2011 Art. 9, 11, 16) | Shown before purchase. Main linings must be listed. Components < 30 % weight that are not main linings may be omitted (Art. 11(2)). "Other fibres" allowed only within Art. 9(2) limits. "100 %", "pure", "all" only when exclusively one fibre (Art. 7). |
| `containsAnimalNonTextile` | Contains non-textile parts of animal origin | Sisältää muuta kuin tekstiiliä olevia eläinperäisiä osia | bool | | LAW (Art. 12) | When true, the exact phrase shows next to the composition. Typical: leather trims, fur, horn buttons, feathers in down (down/feathers are a filling: list them too). |
| `fibreCompositionUnknown` | Material label missing | Materiaalimerkintä puuttuu | bool | | allowed for private second-hand sellers only | Product page then says "Seller could not give the material / Myyjä ei tiedä materiaalia". |
| `sizeSystem` | Size system | Kokojärjestelmä | enum | letter (XXS–4XL), eu_numeric (32–58 women, 44–64 men), jeans_wl (W24–W40 / L28–L36), kids_height (50–176 cm, EN 13402 steps), one_size, bra (e.g. 70B; EU band + cup) | MALVOYA | Option values come from the system's list, so size filters work across shops. |
| `sizeChart` | Size chart | Kokotaulukko | json | rows per size: body measurements in cm (`chest/bust, waist, hips, inside_leg, height, neck`) and/or garment measurements in cm (`length, chest_width, sleeve`) with a flag `measured_on: body/garment` | MALVOYA (business sellers); OPTIONAL (private: give garment measurements instead) | Replaces the generic hard-coded table in `product_detail.dart`. Store can save charts as reusable "size profiles" per brand. |
| `fit` | Fit | Istuvuus | enum | slim, regular, relaxed, oversized; for trousers also skinny, straight, wide, flared | OPTIONAL | |
| `modelInfo` | Model is | Malli | json | `{heightCm, sizeWorn}` | OPTIONAL | "Malli on 176 cm ja käyttää kokoa S". |
| `lengthType` | Length | Pituus | enum | cropped, regular, long; dresses/skirts: mini, knee, midi, maxi | OPTIONAL | |
| `sleeveLength` | Sleeves | Hihat | enum | sleeveless, short, three_quarter, long | OPTIONAL | |
| `neckline` | Neckline | Pääntie | enum | round, v_neck, high, collar, hood, off_shoulder, square | OPTIONAL | |
| `colourFamily` | Colour | Väri | enum (per option) | black, white, grey, beige, brown, blue, navy, green, red, pink, purple, yellow, orange, gold, silver, multi | MALVOYA | Filter value. `colourName` free text for the shop's own name ("Lingon"). |
| `pattern` | Pattern | Kuosi | enum | plain, striped, checked, floral, animal, dotted, graphic, other | OPTIONAL | |
| `lining` | Lining | Vuori | enum | none, partial, full | OPTIONAL | When partial/full, the lining's fibres go into `fibreComposition` (component `lining`). |
| `careInstructions` | Care | Hoito-ohjeet | json | ISO 3758 codes, one per group: `wash` (W95, W60, W40, W40_MILD, W30, W30_MILD, W30_VERY_MILD, HAND, NO_WASH), `bleach` (ANY, OXYGEN_ONLY, NO_BLEACH), `tumble` (NORMAL, LOW, NO_TUMBLE), `natural_dry` (LINE, DRIP_LINE, FLAT, DRIP_FLAT, IN_SHADE variants), `iron` (HIGH, MEDIUM, LOW, NO_IRON), `professional` (P, P_MILD, F, F_MILD, NO_DRY_CLEAN, W, W_MILD, W_VERY_MILD, NO_WET_CLEAN) | OPTIONAL (care labelling is voluntary in the EU) | The app shows text in FI/EN ("Konepesu 40 °C, hienopesu"); drawing the symbols themselves needs a check of GINETEX trademark licensing. |
| `season` | Season | Kausi | enum[] | spring, summer, autumn, winter, all | OPTIONAL | Finnish shoppers filter on winter wear. |
| `occasion` | Occasion | Käyttötilanne | enum[] | everyday, party, work, sport, outdoor, home | OPTIONAL | |
| `vintage` | Vintage | Vintage | bool | made 20+ years ago (seller's statement) | OPTIONAL (second-hand only) | |

Allowed fibre names (Reg. 1007/2011 Annex I; the shop picks from this list, never types free text). Shown in the app language; stored as the key.

| Key | EN | FI | | Key | EN | FI |
|---|---|---|---|---|---|---|
| wool | wool | villa | | acetate | acetate | asetaatti |
| alpaca, llama, camel, cashmere, mohair, angora, vicuna, yak, guanaco, cashgora, beaver, otter | (same; may add "wool" or "hair") | alpakka, laama, kameli, kashmir, mohair, angora, vikunja, jakki, guanako, cashgora, majava, saukko | | alginate | alginate | alginaatti |
| animal_hair / horsehair | animal hair / horsehair (kind may be named) | eläimen karva / jouhi | | cupro | cupro | kupro |
| silk | silk | silkki | | modal | modal | modaali |
| cotton | cotton | puuvilla | | protein | protein | proteiini |
| kapok | kapok | kapokki | | triacetate | triacetate | triasetaatti |
| flax | flax (or linen) | pellava | | viscose | viscose | viskoosi |
| hemp | true hemp | hamppu | | acrylic | acrylic | akryyli |
| jute | jute | juutti | | chlorofibre | chlorofibre | klorokuitu |
| abaca | abaca (Manila hemp) | manilla | | fluorofibre | fluorofibre | fluorokuitu |
| alfa | alfa | esparto (alfaheinä) | | modacrylic | modacrylic | modakryyli |
| coir | coir (coconut) | kookos | | polyamide | polyamide or nylon | polyamidi tai nailon |
| broom | broom | genista | | aramid | aramid | aramidi |
| ramie | ramie | rami | | polyimide | polyimide | polyimidi |
| sisal | sisal | sisali | | lyocell | lyocell | lyocell |
| sunn | sunn | sunhamppu | | polylactide | polylactide | polylaktidi |
| henequen | henequen | henequen | | polyester | polyester | polyesteri |
| maguey | maguey | maguey | | polyethylene | polyethylene | polyeteeni |
| | | | | polypropylene | polypropylene | polypropeeni |
| | | | | polycarbamide | polycarbamide | polyurea |
| | | | | polyurethane | polyurethane | polyuretaani |
| | | | | vinylal | vinylal | vinylaali |
| | | | | trivinyl | trivinyl | trivinyyli |
| | | | | elastodiene | elastodiene | elastodieeni |
| | | | | elastane | elastane | elastaani |
| | | | | glass_fibre | glass fibre | tekstiililasi |
| | | | | elastomultiester | elastomultiester | elastomultiesteri |
| | | | | elastolefin | elastolefin | elasto-olefiini |
| | | | | melamine | melamine | melamiini |
| | | | | other_fibres | other fibres (only as Art. 9(2)/(5) allows) | muut kuidut |

Notes: names read from the 2011 original text in English and Finnish (18 Oct 2026). Later delegated acts added fibre names (e.g. polypropylene/polyamide bicomponent, polyacrylate); add them after checking the consolidated Annex I. Swedish names (needed on the physical label) come from the Swedish language version of the same Annex. "Virgin wool / uusi villa" only under Art. 8. Words like "bamboo" are not fibre names: bamboo viscose is "viscose".

Composition is displayed as `65 % puuvilla, 35 % polyesteri` (descending by weight, same font and size, brand names kept apart: Art. 16).

### 2.3 APPAREL_ACCESSORY (hats, scarves, gloves)

APPAREL minus `sizeChart` (OPTIONAL instead), `fit`, `neckline`, `sleeveLength`, `lengthType`. Keep `fibreComposition` (LAW when ≥ 80 % textile by weight, Reg. 1007/2011 Art. 2(2)(a)), `containsAnimalNonTextile`, `careInstructions`, `colourFamily`, `pattern`, `season`. Size system: one_size, letter, or `headCircumferenceCm` for hats, hand size 6–11 for gloves.

### 2.4 FOOTWEAR (all `shoes-*`)

| Key | EN | FI | Type | Allowed values | Level | Notes |
|---|---|---|---|---|---|---|
| `materialUpper` | Upper | Päällinen | enum[] ≤ 2 | leather, coated_leather, textile, other | LAW\* (Dir. 94/11/EC labelling; shown as main characteristic) | Two values only if no material reaches 80 % (Your Europe guidance). |
| `materialLiningSock` | Lining and insole | Vuori ja sisäpohja | enum[] ≤ 2 | leather, coated_leather, textile, other | LAW\* | |
| `materialOuterSole` | Outer sole | Ulkopohja | enum[] ≤ 2 | leather, coated_leather, textile, other | LAW\* | |
| `materialDetail` | Material details | Materiaalitiedot | text | e.g. "suede", "recycled rubber (GRS certificate …)" | OPTIONAL | "Recycled" needs evidence (§2.12). |
| `sizeSystem` | Size | Koko | enum | eu (16–50, halves allowed), uk, us_w, us_m, kids_eu; `footLengthCm` per size | MALVOYA (EU size) | Option values = EU sizes. |
| `footLengthCm` | Foot length | Jalan pituus | decimal per size | cm | OPTIONAL (MALVOYA for kids' shoes) | Powers "find my size". |
| `width` | Width | Lesti | enum | narrow, standard, wide, extra_wide (or G/H/K) | OPTIONAL | |
| `heelHeightCm` | Heel height | Korkeus | decimal | | OPTIONAL | |
| `closure` | Fastening | Kiinnitys | enum | laces, velcro, zip, slip_on, buckle | OPTIONAL | |
| `waterproof` | Waterproof | Vedenpitävä | enum | no, water_repellent, waterproof_membrane | OPTIONAL | Specific, testable claim; name the membrane if any. |
| `lined_warm` | Warm lining | Lämmin vuori | bool | | OPTIONAL | Winter filter. |
| `colourFamily`, `audience`, `season` | | | | as APPAREL | MALVOYA / OPTIONAL | |

Footwear pictogram codes for the label are the directive's four materials; the app shows words in FI/EN.

### 2.5 BAG and ACCESSORY

| Key | EN | FI | Type | Allowed values | Level |
|---|---|---|---|---|---|
| `mainMaterial` | Material | Materiaali | enum[] | leather, coated_leather, textile, synthetic_leather, plastic, metal, wood, straw, other | MALVOYA |
| `fibreComposition` | Textile composition | Kuitukoostumus | json | as APPAREL | LAW when the product is ≥ 80 % textile (e.g. canvas tote) |
| `containsAnimalNonTextile` | as APPAREL | | bool | | LAW for textile products with leather/fur parts |
| `dimensionsCm` | Size (W × H × D) | Mitat (L × K × S) | json | cm | MALVOYA for bags |
| `closure` | Closure | Sulkeminen | enum | zip, magnet, buckle, open, drawstring | OPTIONAL |
| `strap` | Strap | Hihna | enum[] | handle, shoulder, crossbody_adjustable, backpack, none | OPTIONAL |
| `laptopFitsInch` | Laptop fits | Kannettava mahtuu | int | inches | OPTIONAL |
| `metalSkinContact` | Metal parts touching skin | Ihoa koskettavat metalliosat | bool | | MALVOYA for belts/watches/hair accessories (nickel rule, AB §8) |
| `colourFamily`, `pattern` | | | | | MALVOYA / OPTIONAL |

### 2.6 EYEWEAR and WATCH

EYEWEAR (`accessories-sunglasses`): sunglasses are personal protective equipment under Regulation (EU) 2016/425 (category I). Fields: `uvFilterCategory` (enum 0–4, LAW\*, shown), `ceMarked` (bool, LAW\* must be true), `declarationOfConformityUrl` (OPTIONAL, MALVOYA to have on request), `notForDriving` (bool, LAW\* when category 4: the warning goes into `warnings`), `polarised` (OPTIONAL), `frameMaterial` (OPTIONAL). This regulation is not analysed further in AB; treat as a launch gate checked by an admin.

WATCH (`accessories-watches`): `movement` (quartz, automatic, mechanical, smart → smart watches out of scope: radio equipment), `caseMaterial`, `strapMaterial`, `waterResistance` (enum: none, 3 atm, 5 atm, 10 atm, 20 atm), `metalSkinContact` (nickel rule applies to cases and straps, AB §8), `containsBattery` (bool; batteries law gives producers duties: admin check).

### 2.7 COSMETIC (shared by COSMETIC_MAKEUP, COSMETIC_SKIN, COSMETIC_HAIR, COSMETIC_NAIL, FRAGRANCE)

| Key | EN | FI | Type | Allowed values | Level | Notes |
|---|---|---|---|---|---|---|
| `responsiblePerson` | Responsible person | Vastuuhenkilö | ref → `EconomicOperator` (role `cosmetics_rp`) | name + postal address in the EU | LAW (Reg. 1223/2009 Art. 4, 19(1)(a)) | Shown on the page. Also satisfies GPSR manufacturer/EU contact when it is the same company. |
| `countryOfOrigin` | Country of origin | Alkuperämaa | enum | ISO country | LAW for products imported into the EU (Art. 19(1)(a)) | |
| `nominalContent` | Content | Sisältö | decimal + unit | `ml` or `g` (or `pcs` for multi-item packs); per option | LAW (Art. 19(1)(b)), except packs < 5 g / 5 ml, free samples, single-application packs | Basis of the unit price. |
| `unitPrice` | Unit price | Yksikköhinta | computed | € per litre (ml input) or € per kg (g input), 2 decimals, per option | LAW (VNa 553/2013 §3, §4) when content ≥ 50 ml/50 g | Never stored by hand: `priceCents / content × 1000`. Hidden for < 50 g/ml (§10) and for `pcs`. |
| `durabilityType` | Shelf life | Säilyvyys | enum | best_before (≤ 30 months), pao (> 30 months), not_relevant | LAW (Art. 19(1)(c)) | |
| `paoMonths` | After opening | Avaamisen jälkeen | int | 3, 6, 9, 12, 18, 24, 36 | LAW when `pao` | Shown with the open-jar symbol and "12 kk". |
| `bestBefore` | Best before | Parasta ennen | date (month + year) per stock lot | | LAW when `best_before` | Store must keep it current: Malvoya hides the option when the date has passed (distributor duty Art. 6(2)). |
| `function` | What it is for | Käyttötarkoitus | text {fi, sv, en?} | | LAW unless obvious from presentation (Art. 19(1)(f)); FI and SV | |
| `howToUse` | How to use | Käyttöohje | longtext {fi, sv, en?} | | LAW\* where needed for safe use (FI and SV per Tukes) | |
| `precautions` | Precautions | Varotoimet | longtext {fi, sv, en?} | incl. Annex III–VI warnings (e.g. hair dye allergy warning) | LAW (Art. 19(1)(d)); FI and SV | Rendered in the product safety section and, for strong warnings, above the buy button. |
| `ingredientsInci` | Ingredients | Ainesosat | longtext | INCI names, comma-separated, as on the pack, starting with "Ingredients:"; `(nano)` after nanomaterials; colorants as CI numbers; "may contain / +/-" for shade ranges | LAW on the pack (Art. 19(1)(g)); MALVOYA on the listing (needed so the buyer sees what they buy; see AB §3) | Parsed into an array for search and the allergen finder; the original text is always shown as typed. Store may upload a photo of the panel; typed text still required. |
| `fragranceAllergens` | Fragrance allergens named | Hajusteallergeenit | derived | from INCI list vs. Annex III allergen list | computed | Used for the "contains fragrance allergens" note. Track Reg. (EU) 2023/1545: older products may be sold until 31 July 2028. |
| `keyIngredients` | Key ingredients | Pääainesosat | enum[] ≤ 5 | e.g. hyaluronic_acid, niacinamide, retinol, vitamin_c, ceramides, salicylic_acid, glycolic_acid, peptides, spf_filters, shea_butter | OPTIONAL | Each must appear in the INCI list (validated). Claim "contains X" requires the ingredient to be deliberately present. |
| `freeFrom` | Free from | Ei sisällä | enum[] | only: fragrance (parfum), alcohol, animal_derived, acetone (nail) | OPTIONAL, validated | Rules in §2.7.1. Free text "free from" is not offered. |
| `skinType` | Skin type | Ihotyyppi | enum[] | all, dry, oily, combination, normal, sensitive, mature | OPTIONAL (MALVOYA for skincare) | |
| `skinConcern` | Concern | Huolenaihe | enum[] | hydration, dullness, uneven_tone, blemishes, pores, fine_lines, redness, dark_circles | OPTIONAL | Cosmetic wording only, never disease names (no "acne treatment", "eczema", "rosacea"). |
| `hairType` | Hair type | Hiustyyppi | enum[] | all, fine, thick, curly, coily, straight, coloured, damaged, oily, dry | OPTIONAL (MALVOYA for haircare) | |
| `spf` | SPF | Suojakerroin | enum | 6, 10, 15, 20, 25, 30, 50, 50+ | LAW\* for sun protection products (state the value from the pack) | Also UVA logo flag. Sunscreen claims follow the Commission Recommendation on sunscreen efficacy (not analysed here; admin check). |
| `veganCertified` / `crueltyFreeCertified` | | | via `certifications` only | Leaping Bunny, The Vegan Society trademark, Vegan (EVE) etc., with licence number | OPTIONAL | No plain "vegan" or "cruelty-free" switch (§2.12, AB §3.5). |
| `professionalUse` | Professional use only | Vain ammattikäyttöön | bool | | MALVOYA: such products cannot be sold to consumers on Malvoya | |
| `isTesterOrSample` | Tester or sample | Testeri tai näyte | bool | | MALVOYA: blocks publishing ("not for sale" items) | |
| `sealedUnused` | Sealed and unused | Avaamaton ja käyttämätön | bool | must be true | MALVOYA | No used/opened cosmetics (AB §3.7). |

#### 2.7.1 Free-from rules (validation, from the claims technical document of 3 July 2017, Annex III applicable from 1 July 2019)

| Allowed value | Validation | Message when it fails |
|---|---|---|
| fragrance (parfum) | INCI has no `parfum`, `aroma`, no Annex III fragrance allergen and no ingredient with a perfuming function | "Tuote sisältää hajustetta (esim. Linalool). 'Hajusteeton' ei ole sallittu. / The product contains fragrance (e.g. Linalool), so 'fragrance-free' isn't allowed." |
| alcohol | no `alcohol`, `alcohol denat.`, `ethanol` | likewise |
| animal_derived | no beeswax (`cera alba`), lanolin, carmine (CI 75470), honey (`mel`), milk, keratin, collagen of animal origin, squalane unless plant source stated | asks for confirmation that every ingredient is plant/synthetic origin |
| acetone (nail polish/remover) | no `acetone` | likewise |

Not offered at all, with the reason shown in the editor's help: "free from parabens / phenoxyethanol / silicones (denigrating safe ingredients or often untrue)", "free from [a banned substance]" (mere legal compliance), "free from allergens", "hypoallergenic" (only with dossier evidence, admin-verified), "chemical-free", "toxin-free", "non-toxic", "clean", "natural" without a certificate.

### 2.8 COSMETIC_MAKEUP and COSMETIC_NAIL (shade products)

Shades are **options** (`ProductVariant` rows) with these extra fields:

| Key | EN | FI | Type | Allowed values | Level | Notes |
|---|---|---|---|---|---|---|
| `shadeName` | Shade | Sävy | text ≤ 40 per option | the brand's name/number ("02 Sand") | MALVOYA | |
| `shadeHex` | Swatch colour | Sävynäyte | text `#RRGGBB` per option | picked with an eyedropper from the swatch photo, or typed | MALVOYA | Drawn as the swatch circle. Disclaimer: "Näytön värit voivat poiketa / Colours vary by screen". |
| `shadeImage` | Swatch photo | Sävykuva | image per option | | OPTIONAL (strongly encouraged) | |
| `shadeFamily` | Shade family | Sävyperhe | enum | foundation/concealer: very_fair, fair, light, light_medium, medium, medium_tan, tan, deep, very_deep; lips/nails/eyes: nude, pink, red, coral, berry, plum, brown, orange, purple, blue, green, black, white, clear, glitter, metallic | MALVOYA | Filter. |
| `undertone` | Undertone | Alasävy | enum | cool, neutral, warm, olive | OPTIONAL (MALVOYA for foundation/concealer) | |
| `finish` | Finish | Viimeistely | enum | matte, satin, natural, dewy, glossy, shimmer, metallic | OPTIONAL | |
| `coverage` | Coverage | Peittävyys | enum | sheer, light, medium, full | OPTIONAL (MALVOYA for foundation) | |
| `formulation` | Texture | Koostumus | enum | liquid, cream, powder, stick, gel, mousse, pencil | OPTIONAL | |
| `longwear` | Long-wearing (hours) | Kestävyys (tuntia) | int | only with evidence on request | OPTIONAL | Claim needs evidence (Reg. 655/2013 "evidential support"). |

Colorant "may contain" lists apply to the whole range, so INCI stays on the product, not per shade.

### 2.9 FRAGRANCE

COSMETIC fields plus:

| Key | EN | FI | Type | Allowed values | Level |
|---|---|---|---|---|---|
| `concentration` | Concentration | Tuoksun vahvuus | enum | parfum (extrait), eau_de_parfum, eau_de_toilette, eau_de_cologne, body_mist, perfume_oil | MALVOYA |
| `content` (per option) | Size | Koko | decimal ml | 5–200 | LAW (nominal content) |
| `olfactoryFamily` | Scent family | Tuoksuperhe | enum[] ≤ 2 | floral, fruity, citrus, green, aromatic, woody, oriental_amber, gourmand, musky, aquatic, leather, chypre, fougere, spicy | OPTIONAL (MALVOYA for parfum/EDP/EDT) |
| `notesTop`, `notesHeart`, `notesBase` | Top, heart, base notes | Lähtö-, sydän- ja pohjatuoksut | text[] | free text, ≤ 6 each | OPTIONAL |
| `launchYear` | Launched | Julkaisuvuosi | int | | OPTIONAL |
| `refillable` | Refillable | Täytettävä | bool | | OPTIONAL (specific, factual) |

Unit price for fragrance: € per litre per option, e.g. 50 ml at 89,00 € → "1 780,00 €/l".

### 2.10 JEWELLERY

| Key | EN | FI | Type | Allowed values | Level | Notes |
|---|---|---|---|---|---|---|
| `metal` | Metal | Metalli | enum | gold, white_gold, rose_gold, silver_925, sterling_silver, platinum, palladium, stainless_steel_316l, titanium, brass, copper, aluminium, alloy_unknown, none | MALVOYA | |
| `fineness` | Fineness | Pitoisuus | enum | gold 375/585/750/916/999; silver 800/830/925/999; platinum 950 | MALVOYA when precious metal | Finnish precious-metals rules (fineness and responsibility marks) apply: admin check with Tukes guidance before launch. |
| `plating` | Plating | Pinnoite | enum | none, gold_plated, gold_vermeil, rhodium_plated, silver_plated, pvd | MALVOYA | Plated items are not "gold". |
| `nickelBasis` | Nickel safety | Nikkeliturvallisuus | enum | test_report_en1811 (release below limit), supplier_declaration, nickel_free_material (titanium, 999 silver, ≥ 585 gold), not_known | MALVOYA (LAW\* for items in prolonged skin contact: REACH Annex XVII entry 27) | "Nickel-free / Nikkelitön" chip only for `nickel_free_material` or a test report; `not_known` blocks publishing for business sellers of new items. |
| `leadCadmiumBasis` | Lead and cadmium | Lyijy ja kadmium | enum | supplier_declaration, test_report, precious_metal_only | MALVOYA for new non-precious jewellery | REACH entries 23 and 63. |
| `stone` | Stone | Kivi | enum[] | none, diamond, lab_diamond, sapphire, ruby, emerald, pearl (natural/cultured), freshwater_pearl, crystal_glass, cubic_zirconia, semi_precious (name), synthetic | OPTIONAL | Synthetic/lab stones must say so. |
| `ringSize` | Ring size | Sormuskoko | option | Finnish/EU sizes 14–22 (inner diameter mm) | MALVOYA for rings | |
| `chainLengthCm` | Length | Pituus | decimal | | MALVOYA for necklaces/bracelets | |
| `forPiercing` | For pierced ears/body | Lävistykseen | bool | | MALVOYA | Stricter nickel limit; hygiene seal on. |
| `hallmarked` | Hallmarked | Leimattu | bool | | OPTIONAL | |

### 2.11 KIDS_SAFETY (added when audience includes kids or baby)

| Key | EN | FI | Type | Values | Level | Notes |
|---|---|---|---|---|---|---|
| `ageRange` | Age | Ikä | enum | 0–3 months … 14 years, or height 50–176 cm | MALVOYA | |
| `cordsDrawstrings` | Cords and drawstrings | Narut ja kiristysnyörit | enum | none, compliant_en14682, present_hood_neck (blocks for < 7 years / ≤ 134 cm) | MALVOYA (implements GPSR safety via EN 14682) | Store declaration; admin spot checks with photos. |
| `smallParts` | Small detachable parts (babies) | Irtoavat pienet osat | enum | none, secure_tested, present | MALVOYA for baby | `present` blocks publishing for baby clothes. |
| `costumeIsToy` | Fancy-dress costume | Naamiaisasu | bool | | MALVOYA | Costumes are toys: out of scope until a toy template exists. |

### 2.12 Certifications (replaces `isEcoFriendly`)

`ProductCertification`: `scheme` (enum below), `licenceNumber` (text, required), `holderName` (text, required: whose licence it is), `scope` (enum: whole_product, material_component, packaging — required, and shown), `component` (text, when scope is a component, e.g. "cotton shell"), `validUntil` (date), `evidence` (uploaded certificate PDF/image, private), `verifiedBy`, `verifiedAt` (admin), `publicVerifyUrl` (OPTIONAL, scheme's own lookup page).

A chip is shown only when `verifiedAt` is set and `validUntil` has not passed. The chip text names the scheme and licence on the product page itself ("Joutsenmerkki · lisenssi 1234 5678"), because the KKV draft guideline (comment period to 21 Oct 2026) says a specification cannot sit behind a link.

| Scheme key | Name EN | Name FI | What it is | Chip may say | Allowed for |
|---|---|---|---|---|---|
| `eu_ecolabel` | EU Ecolabel | EU-ympäristömerkki | EN ISO 14024 type I, Reg. 66/2010: recognised excellent environmental performance | the scheme name; generic claims only those the criteria cover | textiles, footwear, cosmetics (rinse-off & leave-on groups) |
| `nordic_swan` | Nordic Swan Ecolabel | Joutsenmerkki | official Nordic type I ecolabel | as above | textiles, cosmetics |
| `gots` | GOTS (organic) | GOTS (luomu) | private third-party textile scheme | "GOTS-sertifioitu: [made with organic / organic]" + licence | textiles |
| `ocs` | Organic Content Standard | OCS | content claim scheme | "Sisältää X % luomupuuvillaa (OCS)" | textiles |
| `grs` / `rcs` | Global / Recycled Claim Standard | GRS / RCS | recycled content | "Sisältää X % kierrätettyä polyesteriä (GRS)" | textiles, footwear, bags |
| `oeko_tex_100` | OEKO-TEX Standard 100 | OEKO-TEX Standard 100 | tested for harmful substances (not an environmental claim) | "Testattu haitallisten aineiden varalta (OEKO-TEX 100)" | textiles |
| `bluesign` | bluesign | bluesign | chemical management in production | scheme name + scope | textiles |
| `rws` / `rds` | Responsible Wool / Down Standard | RWS / RDS | animal welfare | scheme name | wool, down |
| `fsc` | FSC | FSC | forest products (e.g. viscose/lyocell feedstock, packaging) | scheme name + scope | components |
| `fairtrade` | Fairtrade | Reilu kauppa | social certification | "Fairtrade-sertifioitu puuvilla" | cotton, gold |
| `leaping_bunny` | Leaping Bunny | Leaping Bunny | cruelty-free supply-chain scheme | "Leaping Bunny -hyväksytty" | cosmetics |
| `vegan_society` | Vegan Society trademark | Vegan Society -merkki | vegan product registration | "Vegan Society -rekisteröity" | cosmetics, footwear, bags |
| `cosmos` | COSMOS Organic / Natural | COSMOS | organic/natural cosmetics standard | scheme name + level | cosmetics |
| `natrue` | NATRUE | NATRUE | natural cosmetics label | scheme name | cosmetics |
| `avainlippu` | Key Flag (Avainlippu) | Avainlippu | Finnish origin label (not a sustainability label) | "Avainlippu – suomalaista työtä" | any |

Scheme facts above are from general knowledge and were not re-read this session; verify each scheme's public rules and licence lookup before enabling it. A scheme is only added to the enum after an admin has confirmed it meets the EU definition of a "certification scheme" (third-party verified, open, with sanctions) or is set by a public authority (AB §5).

Also OPTIONAL, specific and evidence-backed (not a chip, a line in "Materials"): `recycledContentPercent` per component with `evidence` (a GRS/RCS certificate or supplier document). Shown as "Sisältää 60 % kierrätettyä polyesteriä / Contains 60 % recycled polyester", never as "eco".

### 2.13 Second-hand condition (all non-beauty templates)

| Value | EN | FI | Requirements |
|---|---|---|---|
| NEW | New, unused | Uusi, käyttämätön | with or without tags (`hasTags` bool, OPTIONAL) |
| LIKE_NEW | Like new | Kuin uusi | no visible wear; defects note OPTIONAL |
| GOOD | Good | Hyvä | light signs of use; **defects note required** ("Ei virheitä" is allowed as an explicit statement) |
| FAIR | Fair | Kohtalainen | visible wear; **defects note and at least one defect photo required** |
| POOR (legacy) | Worn | Kulunut | as FAIR; not offered for new listings |

Extra fields: `defectsNote` (text ≤ 300, FI/EN free), `defectPhotos` (image[]), `measuredGarment` (json: actual garment measurements in cm, MALVOYA for second-hand clothing because original size labels vary), `originalSizeLabel` (text), `authenticity` (enum: receipt, original_packaging_and_cards, authentication_service_report, none) — MALVOYA for brands on the high-risk list (luxury bags, watches, designer clothing, premium sneakers); `none` keeps the listing in admin review.

### 2.14 Claims linter (runs on name, description, shade names, imported tags)

The editor and importer flag these words and ask the store to replace them with a specific, verifiable fact or a certificate, blocking publish until resolved:
- Generic green: eco, eko-, ekologinen, ekoystävällinen, ympäristöystävällinen, luontoystävällinen, vihreä (as a claim), kestävä, kestävästi, vastuullinen, vastuullisesti tuotettu, ilmastoystävällinen, hiilineutraali, ilmastoneutraali, hiilipositiivinen, biohajoava, kompostoituva (without standard), eco-friendly, environmentally friendly, green, sustainable, responsible, conscious, planet-friendly, climate neutral, carbon neutral, biodegradable, natural (without certificate).
- Medical: hoitaa, parantaa, lääke-, ekseema, atooppinen (as a treatment claim), akne-hoito, psoriasis, anti-bakteerinen, desinfioi, treats, cures, heals, eczema, acne treatment, psoriasis, antibacterial, kills germs, hair regrowth.
- Free-from outside §2.7.1, "hypoallergeeninen/hypoallergenic", "dermatologisesti testattu" without evidence (allowed only with the store's confirmation that it holds a test report).
- Legal-minimum boasts: "ei testattu eläimillä / not tested on animals" without a certificate (animal testing for cosmetics is banned in the EU anyway, so on its own it presents a legal requirement as a distinctive feature), "CE-merkitty" for products that must be CE-marked, "paraben-free" etc.

---

## 3. Search filters and sort options per category

Patterns observed at Zalando, Boozt (fashion) and Sephora, Lyko (beauty), described in our own terms:
- Filters come from the category's attributes, not one global list; the first 4–6 chips are the most used in that category, the rest sit behind "All filters".
- Sizes are a tappable grid of the system's sizes (only sizes in stock), with "my sizes" remembered.
- Colour filters show colour dots; beauty shade filters show shade-family swatches.
- Beauty shops lead with product type, skin/hair type, concern, key ingredient and brand; fashion shops lead with size, colour, brand, price, material.
- Every filter shows the result count before applying; empty values are hidden.
- Sorting is short: recommended, newest, price low/high, (beauty) best rated, (local) nearest.

Malvoya's own additions everywhere: **Nearest / Lähimmät** and **Delivery today / Toimitus tänään** (open store within reach), **Reserve & collect / Nouda kaupasta**, **Business seller / Yritysmyyjä** vs **Private seller / Yksityinen myyjä**.

| Category group | First chips (in order) | Under "All filters" | Sort |
|---|---|---|---|
| Clothing | Size, Colour, Price, Brand, Second-hand | Material (fibre), Fit, Length, Sleeve, Pattern, Season, Occasion, Condition, Audience, Certificates, Made in Finland | Recommended, Newest, Price ↑, Price ↓, Nearest |
| Shoes | EU size, Colour, Price, Brand | Width, Upper material, Heel height, Closure, Waterproof, Warm lining, Condition, Audience | as Clothing |
| Bags | Colour, Price, Brand, Material | Size class (S/M/L from dimensions), Strap type, Closure, Laptop fits, Condition | as Clothing |
| Accessories | Type, Colour, Price, Brand | Material, Season, UV category (sunglasses), Water resistance (watches), Condition | as Clothing |
| Jewellery | Type, Metal, Price | Plating, Stone, Nickel-free (verified), Ring size, Length, Condition, Brand | as Clothing |
| Makeup | Product type, Brand, Shade family, Price | Undertone, Finish, Coverage, Formulation, Free from (validated values), Certificates (vegan/cruelty-free schemes) | Recommended, Newest, Price ↑, Price ↓, Unit price ↑ (€/l, €/kg), Best rated |
| Skincare | Product type, Skin type, Concern, Brand, Price | Key ingredient, SPF, Free from, Content (ml range), Certificates, Audience | as Makeup |
| Haircare | Product type, Hair type, Brand, Price | Key ingredient, Free from, Content, Certificates | as Makeup |
| Fragrance | Concentration, Scent family, Brand, Price | Size (ml), Audience (women/men/unisex), Notes (search), Gift set | Recommended, Newest, Price ↑, Price ↓, Unit price ↑ |
| Second-hand | Category, Size, Condition, Price, Brand | Designer only, Vintage, Authenticity checked, Measurements range, Audience | Newest (default), Price ↑, Price ↓, Nearest |

Backend shape: `GET /products/search?category=<slug>&attr[fibre]=cotton&attr[shadeFamily]=nude&...` with an allow-list per template (validated by Zod), and a facets endpoint returning values with counts for the current result set. Every new filter path needs an index (CLAUDE.md "Scaling foundations"): store filterable attributes in a typed table (`ProductAttribute {productId, key, valueText, valueNum}` with `@@index([key, valueText])`) or a GIN-indexed JSONB column; decide in the backend round.

---

## 4. Minimum photo set per category

"Minimum" = needed to publish (MALVOYA). Photos are taken on a plain, light background, no filters that change colour; the first photo is the cover.

| Category | Minimum (to publish) | Recommended |
|---|---|---|
| Clothing (new) | 1 front, 1 back, 1 detail (fabric or print close-up) | on-model front with model height/size, care/composition label, side view |
| Clothing (second-hand) | front, back, composition/size label (or a note that it is missing), each defect | flat-lay with a tape measure |
| Shoes | side (outer), pair from the front, sole | top-down, heel, inside label with size |
| Bags | front, back, inside | side (depth), strap, on the shoulder for scale, label/serial for designer items |
| Accessories | front, detail | worn (scale), label |
| Jewellery | product on plain background, detail (clasp/stamp) | worn for scale, hallmark close-up, packaging |
| Makeup | product (pack), swatch (on skin or on paper) per shade | swatches on several skin tones if available, texture close-up, open product, ingredient panel |
| Skincare / Haircare | product front, back-of-pack or ingredient panel | texture, open product, size in hand |
| Fragrance | bottle, box (front) | box back (ingredients, batch area), sizes side by side |
| Second-hand designer | all of the category's, plus logo, serial/date code, authenticity card or receipt | close-ups of hardware and stitching |

---

## 5. UX recommendations (priority order)

Each item says what the law needs (L) or what the shopper needs (S). The customer product page today is `Malvoya_customer/lib/screens/product_detail.dart`; the store editor is `malvoya_vendor/lib/screens/product_editor.dart`.

### 5.1 Customer product page

1. **Remove the "Eco-friendly / Ympäristöystävällinen" chip** and the eco filter/tile (L, AB §5). Ship this first: the ban has applied since 27 Sept 2026.
2. **Unit price under the price** (L, AB §4): grey, smaller, separate from the price, per selected option: `89,00 €` / `1 780,00 €/l`. Updates when the shade or size changes; shown for sale prices too.
3. **"Product safety & manufacturer / Tuoteturvallisuus ja valmistaja" section** (L, AB §1): collapsed row like "Seller information" today, opening a sheet with manufacturer name, postal and email address; EU responsible person when relevant; model/type and EAN; warnings in Finnish and Swedish (language toggle FI | SV | EN); label photos. A short "Warnings" line appears directly above the buy bar when the product has strong warnings (e.g. hair dye allergy test).
4. **Materials block** (L, AB §2): composition in the product's main facts, above the fold, not inside the description: "65 % puuvilla, 35 % polyesteri · Vuori: 100 % viskoosi" and the animal-parts phrase when set. Footwear: upper / lining / sole.
5. **Ingredient panel** (L/S, AB §3): "Ainesosat / Ingredients" row with the full INCI text as given by the shop, plus a search box: "Etsi ainesosaa / Find an ingredient" (e.g. "linalool"), highlighting matches. A "Hajusteallergeenit / Fragrance allergens" line lists Annex III allergens found. Fixed disclaimer: "Ainesosaluettelo on myyjän antama. Tarkista aina pakkauksen merkinnät. Tämä ei ole lääketieteellistä neuvontaa. / The ingredient list is provided by the seller. Always check the label on the pack. This is not medical advice." Also content, PAO/best before, function, how to use, precautions, responsible person.
6. **Returns badge** (L, AB §6), in the facts area and repeated in the bag/checkout line: for hygiene-sealed items "Hygieniasinetöity – ei palautusoikeutta, jos sinetti avataan / Hygiene seal — can't be returned once the seal is opened" with a one-line "why"; for others "14 päivän palautusoikeus / 14-day returns" (business sellers) or "Yksityinen myyjä – ei lakisääteistä palautusoikeutta / Private seller — no statutory returns".
7. **Shade picker with swatches** (S): a row of circles (hex) with the shade name under the selected one; tap to switch the photo to the shade image; out-of-stock shades crossed out; shade family filter inside the picker for ranges > 12 shades.
8. **Size: the shop's own chart, and "Find my size / Löydä kokosi"** (S): replace the hard-coded generic EU table with the product's `sizeChart`. "Find my size" asks for 2–3 body measurements in cm (saved on the phone only) and highlights the size whose range contains them, or the two nearest sizes with "between sizes — check fit: slim". Shoes: foot length in cm → EU size. Second-hand: show the garment's measured cm.
9. **Certified-claims chips** (L, AB §5): each chip names the scheme and licence number visibly ("GOTS · CU 123456"); tapping shows holder, scope ("koskee: puuvillakangas / applies to: cotton shell"), valid-until and a link to the scheme's own lookup. Neutral styling (no green leaves).
10. **Report this product / Ilmoita tuotteesta** (L, AB §1, DSA notice): in the product's "…" menu: reasons "Vaarallinen tuote / Unsafe", "Väärennös / Counterfeit", "Harhaanjohtava / Misleading", "Muu laiton / Other illegal".
11. **Condition block for second-hand** (S/L): condition with its definition, defects note, defect photos, measured size, authenticity basis for designer items.
12. **Recall banner** (L): on a recalled product (for buyers who open it from an order) a red "Tuotteen turvallisuuteen liittyvä takaisinveto / Product safety recall" banner linking to the notice.

### 5.2 Store app product editor

1. **Pick the category first, then a template.** Step 1 is a searchable category picker (the §1.3 tree, recent categories on top). The form then shows only the fields of that template, in this order: photos → basics (name, brand, price, options) → legal facts (materials / ingredients / content…) → safety & manufacturer → extras. Required fields carry a small "Pakollinen / Required" tag and the reason on tap ("EU:n tekstiiliasetus / EU textile regulation").
2. **Reusable records**: manufacturers/responsible persons, size charts ("size profiles" per brand), care sets, and composition presets ("Sama kuin edellinen tuote / Same as previous product"). For own-brand/handmade shops, the store itself is offered as the manufacturer.
3. **Fibre composition builder**: component tabs (Main, Lining, Filling…), each with fibre rows chosen from the Annex I list and a percentage; a live preview of the label text; the save button stays disabled until each component sums to 100 %.
4. **Bulk options**: a grid to paste or type sizes × colours with stock in one go; for beauty, a shade table (name, hex via eyedropper on the swatch photo, family, undertone, stock, EAN) with paste-from-spreadsheet; for fragrance, content/price rows (30/50/100 ml) with the unit price computed live.
5. **INCI box**: paste the list as printed; the editor splits it, flags unknown names ("Tarkista: 'Aqua (Water)'"), checks that key ingredients are present and validates free-from choices (§2.7.1).
6. **Claims linter** (§2.14) inline under name and description with a suggested specific alternative.
7. **Validation messages** (examples, FI / EN):
   - "Koostumus on 95 %. Prosenttien summan on oltava 100. / Composition adds up to 95 %. It must total 100."
   - "Lisää valmistajan nimi ja osoite. EU:n tuoteturvallisuusasetus vaatii ne verkkokaupassa. / Add the manufacturer's name and address. EU product safety law requires them online."
   - "Valmistaja on EU:n ulkopuolella: lisää vastuuhenkilö EU:ssa. / The manufacturer is outside the EU: add the EU responsible person."
   - "Varoitukset tarvitaan suomeksi ja ruotsiksi. / Warnings are needed in Finnish and Swedish."
   - "Anna sisältö (ml tai g), jotta litra- tai kilohinta voidaan näyttää. / Enter the content (ml or g) so the price per litre or kg can be shown."
   - "'Ekologinen' on yleinen ympäristöväittämä, joka on kielletty ilman tunnustettua ympäristömerkkiä. Kerro tarkka tieto (esim. '60 % kierrätettyä polyesteriä, GRS') tai lisää sertifikaatti. / 'Eco' is a generic green claim, banned without a recognised ecolabel. State a specific fact or add a certificate."
   - "Lasten vaatteessa ei saa olla nyörejä hupussa tai kaulan alueella (alle 7 v). / Children's clothes for under-7s can't have cords in the hood or neck area."
   - "Parasta ennen -päiväys on mennyt: vaihtoehto piilotetaan. / The best-before date has passed: this option is hidden."
8. **Completeness meter** per product ("Valmis julkaistavaksi / Ready to publish" vs a list of what's missing), and a store-level list "Tuotteet, joista puuttuu pakollisia tietoja / Products missing required information" (extends the existing `filter=drafts` list).
9. **Private sellers** see a lighter form: brand, category, condition, defects, measurements, photos; legal-label fields become "if you have the label" with a photo option.

### 5.3 Import mapping (Shopify / WooCommerce / CSV → spec)

| Spec field | Shopify (`/products.json`) | WooCommerce (wc/v3) | CSV column (new/old) |
|---|---|---|---|
| categorySlug | `product_type`, `tags`, `title` via §1.4 | `categories[].name` (deepest), `tags` | `category_slug` (new), `category` |
| audience | tags/product_type words | categories/tags words | `audience` |
| brand | `vendor` | `brands` (plugin) or attribute "Brand/Merkki" | `brand` |
| name / description | `title` / `body_html` (to text, as today) | `name` / `description` | `name` / `description` |
| options size / colour / shade / content | `options[].name` + variant `option1..3` (§1.4 dimension names) | `attributes` with `variation: true` | `size`, `colour`, `shade`, `shade_hex`, `content_ml`, `content_g` |
| gtin | variant `barcode` (as today) | `global_unique_id` or meta `_gtin`/EAN plugins | `gtin` |
| price, stock, images | as today | as today | as today |
| fibreComposition | not in the public feed: parsed from `body_html` lines like "Materiaali: 95 % puuvilla, 5 % elastaani" as a **suggestion** the store confirms | attribute "Materiaali/Material" (same parser) | `composition` ("95% cotton, 5% elastane"; component prefix "lining:") |
| ingredientsInci | from `body_html` after "Ingredients:/Ainesosat:" as a suggestion | attribute or description, same | `ingredients` |
| nominalContent | variant option values with ml/g, or title ("50 ml") | attribute "Koko/Size" with units | `content_ml` / `content_g` |
| condition / isSecondHand | tags (`USED_TAG`) | tags/categories | `condition` |
| manufacturer, responsible person, warnings, PAO, care | not available in feeds | meta fields if the shop has them | `manufacturer_name`, `manufacturer_address`, `manufacturer_email`, `eu_rp_name`, `eu_rp_address`, `eu_rp_email`, `warnings_fi`, `warnings_sv`, `pao_months`, `best_before`, `care_codes` |

Every imported draft gets a per-product "missing required fields" list in the import report; drafts stay hidden (as today) and cannot be published until complete. Parsed suggestions are never auto-accepted for LAW fields.

---

## 6. Data model sketch (for the backend round; not built)

- `Product`: add `categorySlug`, `audience[]`, `brand`, `productModel`, `manufacturerId`, `euResponsiblePersonId`, `cosmeticsRpId`, `warnings Json`, `countryOfManufacture`, `hygieneSeal`, `hygieneSealDescription`, `attributes Json` (template-validated), `defectsNote`, `authenticity`; deprecate `category` (kept read-only during migration), `isEcoFriendly` (remove from API and UI now, drop the column later).
- `ProductVariant`: add `shadeName`, `shadeHex`, `shadeFamily`, `shadeImage`, `contentAmount`, `contentUnit (ml|g|pcs)`, `gtin`, `bestBefore`.
- `OrderItem`: snapshot `hygieneSeal`, `unitPriceText`, `productModel`, `gtin`, `batchOrSerial` at purchase (recalls and returns must know what was sold).
- New: `EconomicOperator`, `ProductCertification`, `ProductAttribute` (or JSONB + GIN), `Category` (seeded tree with names, icon, tile, template; served by `GET /categories`), `ProductSafetyCase` + `SafetyNotification` (recall flow, AB §1.6), `ProductNotice` (DSA/GPSR notices from "Report this product").
- `Store`: remove `ECO_FRIENDLY` and `isEcoFriendly`; add `sellsSecondHand`, `makesOwnProducts`, `safetySelfCertifiedAt`.
- e2e checks to add: composition must total 100; unit price shown/hidden around 50 ml; eco flag absent from all responses; hygiene snapshot drives return rules; recall notifies every buyer of the product; facet endpoint bounded.
