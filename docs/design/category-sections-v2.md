# Home categories v2: audiences, age groups, collections and services (owner request 22 Oct 2026)

Extends `docs/compliance/product-data-spec.md` and `docs/design/home-and-drops-redesign.md`.

## 1. Delivery slots: no invented times
- `DELIVERY_SLOTS` default becomes **empty**: scheduled delivery is off until the owner sets real windows in env/admin.
- Rail titles come from the configured slots ("Delivered today 18–20" / "Toimitus tänään 18–20"). With no slots, a "Delivered today / Tänään perille" rail shows only when same-day delivery is possible (stores open + couriers online); otherwise it hides.
- No screen, copy or legal text may name a time window that isn't configured.

## 2. Audience and age groups (the switch at the top of Home and a filter everywhere)
| Switch | Includes | Notes |
|---|---|---|
| All | everything | default |
| Women / Naiset | women + unisex | |
| Men / Miehet | men + unisex | |
| Kids / Lapset | opens a second row: Baby 0–2 v / Vauvat, Toddler 2–4 v / Taaperot, Kids 4–8 v / Lapset, Junior 8–14 v / Juniorit | product field `ageGroup`; kids' sizes in cm (50–176) |
| Teens / Nuoret | 13–17 styles and sizes (XS–L, 146–176) | content rules below |

Product data: `audience` (WOMEN | MEN | UNISEX | KIDS) + optional `ageGroup` (BABY | TODDLER | KIDS | JUNIOR | TEEN | ADULT). Fit collections (filters + Home collections, not separate trees): **Plus size / Isot koot**, **Maternity / Äitiys**, **Petite**, **Tall**, **Adaptive clothing / Esteettömät vaatteet** (easy closures, seated fit).

Responsible rules for young people:
- No profiling-based recommendations or ads to users known or likely to be under 18 (DSA Art. 28).
- Kids and teen collections never use body-image wording.
- Beauty and fragrance are not promoted in Kids sections.
- Kids' clothing must pass the drawstring and safety gates in the compliance spec.

## 3. Product categories: additions to the 10 tiles
Additions to the existing tree (slugs FI/EN in the spec):
- **Clothing:** + Swimwear & beachwear / Uima-asut, Nightwear & loungewear / Yöasut, Outdoor & rainwear / Ulkoilu- ja sadevaatteet, Sauna textiles? (no: home textiles are out of scope), Workwear / Työvaatteet, Traditional & festive wear / Juhlavaatteet (including national-costume accessories sold as clothing).
- **Shoes:** + Winter boots / Talvikengät, Rubber boots / Kumisaappaat, Kids' first shoes / Ensikengät.
- **Accessories:** + Winter accessories / Pipot, hanskat ja huivit, Hair accessories / Hiusasusteet, Phone accessories? (no: out of scope).
- **Makeup / Skincare / Haircare:** + **Men's grooming / Miesten hoito** (beard, shaving, skincare for men), **Body care / Vartalonhoito**, **Sun care / Aurinkosuojaus** (own subcategory, seasonal), **Hair tools / Hiustenmuotoilulaitteet** (electrical: needs CE info in the safety block).
- **Fragrance:** + Home fragrance? (no: out of scope), Body mists / Vartalosuihkeet.
- **New tile, Sport & outdoor / Urheilu ja ulkoilu:** activewear, running, gym, hiking, ski & winter sports clothing (clothing and shoes only, no equipment).

## 4. Collections (curated rails and tiles; a saved filter, not a new product type)
Shown on Home below categories only when they have ≥ 8 items nearby:
- **Seasons:** Winter essentials / Talven tärkeimmät (Oct–Mar), Spring & rain / Kevät ja sade, Summer / Kesä, Festival season / Festarit (Jun–Aug).
- **Occasions:** Party & wedding guest / Juhliin, Work / Töihin, Graduation & school start / Valmistujaiset ja koulun alku (May–Aug), Holiday gifts / Joululahjat (Nov–Dec).
- **Gifts by price:** Under 25 € / Alle 25 €, 25–50 €, 50 €+ (uses gift-friendly items: beauty sets, accessories, jewellery).
- **Made in Finland / Suomessa valmistettu** and **Handmade / Käsintehty**: only with the seller's origin declaration (an origin claim, not a sustainability claim).
- **Certified / Sertifioidut**: only admin-verified certificates (see compliance spec).
- **Second-hand finds / Käytetyt löydöt**: condition chips.
- **Brands / Merkit**: an A–Z brand index from product data.
- **Beauty by concern / Iho- ja hiustarpeet**: dry skin, sensitive skin, blemish-prone, curly hair… This describes *product purpose*, not medical claims (Reg. 655/2013).

## 5. Services row on Home (things people *do*, not buy)
| Tile | Opens | Shown when |
|---|---|---|
| Returns & refunds / Palautukset | the returns hub: start a return, track returns, refund status, rules (14 days, hygiene seal) | always (guest → sign-in) |
| Track order / Seuraa tilausta | the active order or order list | always |
| Reserve & collect / Varaa ja nouda | catalogue filtered to pickup-ready shops | when ≥ 1 shop offers pickup nearby |
| Size & shade help / Koko- ja sävyapu | how size charts and shade swatches work; measure guide | always |
| Help & contact / Apua | the support hub | always |

Services are a horizontal row of small round tiles under the categories, visually distinct from product tiles (outline style), so people never confuse them with shopping categories.

## 6. Home order (updated)
Search → audience switch (+ kids age row) → active order → **Shop by category** (11 tiles incl. Sport & outdoor; first 9 visible + "All categories") → **Services** row → seasonal collection (one, the current season) → Delivered today (if possible) → New in near you → Second-hand finds → Gifts by price (Nov–Dec, or always as one tile) → Shops near you.
