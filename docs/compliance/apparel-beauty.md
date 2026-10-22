# Selling apparel, footwear, accessories, jewellery and beauty on Malvoya: legal requirements

Written 18 Oct 2026 for Malvoya's product, backend and store-onboarding work. Plain English, with a short Finnish summary after each section.

**This is a compliance working document, not legal advice.** It was prepared from the official texts listed in §12 (each with the date it was read). Before launch, have a Finnish lawyer confirm the points marked *verify*. Malvoya has no Y-tunnus yet; company details below are `[PLACEHOLDERS]`.

Companion: `docs/compliance/product-data-spec.md` ("Spec §…"), which turns everything here into categories, fields and screens.

How each section is laid out:
- **Malvoya must** — duties of the marketplace provider.
- **The shop must** — duties of the seller (trader), usually as "distributor" of goods made by someone else, or as "manufacturer" for own-brand and handmade goods.
- **Product page needs** / **Store editor needs** — what to build.

---

## Top 10 legal must-dos, ranked

1. **Remove the "eco / Ekologinen / Ympäristöystävällinen" flag, filter, Home tile and store category now** (§5). Since 27 Sept 2026 a generic environmental claim without recognised excellent environmental performance is banned outright (Directive (EU) 2024/825, implemented in Finland by Act 573/2026 amending the Consumer Protection Act). Malvoya shows the claim itself, based on an unverified seller switch.
2. **Show the GPSR product-safety information on every listing** (§1): manufacturer name, postal and electronic address; the EU responsible person when the manufacturer is outside the EU; product identification (picture, type, any identifier); warnings and safety information in Finnish and Swedish. Malvoya must design the editor so shops can give this (GPSR Art. 19, 22(9)–(10)).
3. **Set up Malvoya's product-safety processes** (§1): a single contact point for authorities (registered on the Safety Gate Portal) and one for consumers; internal procedures; act on authority orders within 2 working days and on product-safety notices within 3 working days; a "Report this product" notice button; shop self-certification; suspension of repeat offenders (GPSR Art. 22(1)–(11)).
4. **Build the recall and safety-warning flow** (§1.6): directly notify every identifiable buyer, publish recalls in the app, use the legal recall-notice format, notify authorities through the Safety Business Gateway (GPSR Art. 22(12), 35–37).
5. **Fibre composition with percentages, using only the legal fibre names, visible before purchase** for every textile product, plus "Contains non-textile parts of animal origin" when relevant (Reg. 1007/2011 Art. 5, 9, 12, 16) (§2).
6. **Cosmetics: show the label facts before purchase and check them as a distributor** (§3): ingredient list (INCI), nominal content, best-before or period after opening, precautions, function, responsible person; Finnish and Swedish where the law requires; no medical or misleading claims; sealed, unused, in-date products only.
7. **Unit price per litre or per kilogram** next to the price for cosmetics and fragrance sold by volume or weight (≥ 50 ml / 50 g), per option, also on sale prices. In Finland it is per kg / per litre, **not** per 100 ml / 100 g (§4).
8. **Disclose the hygiene-seal exception before purchase and handle it in returns** (§6): only for genuinely hygiene-sealed goods (cosmetics, fragrance, piercing jewellery and earrings in sealed packs), never for clothing in general (CJEU C-681/17).
9. **Children's clothing and jewellery chemical safety gates** (§8): no cords/drawstrings in the hood or neck area for under-7s (EN 14682 via GPSR); nickel release, lead and cadmium limits for jewellery (REACH Annex XVII entries 27, 63, 23); the REACH Art. 33 right-to-know answering route.
10. **Keep seller identity and consumer-rights disclosure right, and police counterfeits** (§7): business/private seller shown on every listing with the consequence for consumer rights (Consumer Protection Act ch. 6 §9 a), trader information on product pages, notice-and-action for counterfeits and repeat-infringer suspension.

Ten-point summary in Finnish:
1. Poista "eko/ympäristöystävällinen"-merkintä, -suodatin, -etusivun ruutu ja kauppakategoria heti. 2. Näytä jokaisessa tuotteessa valmistajan tiedot, EU-vastuuhenkilö tarvittaessa, tuotteen tunniste ja varoitukset suomeksi ja ruotsiksi. 3. Perusta tuoteturvallisuuden yhteyspisteet ja prosessit (viranomaismääräys 2 työpäivässä, ilmoitukset 3 työpäivässä). 4. Rakenna takaisinvetoprosessi, joka tavoittaa jokaisen ostajan. 5. Kuitukoostumus prosentteineen ennen ostoa. 6. Kosmetiikan pakkausmerkintätiedot ennen ostoa ja jakelijan tarkistukset. 7. Litra- tai kilohinta (ei 100 ml / 100 g). 8. Hygieniasinettipoikkeus kerrotaan ennen ostoa, vain aidosti sinetöidyille tuotteille. 9. Lastenvaatteiden nyörit ja korujen nikkeli, lyijy ja kadmium. 10. Myyjän tiedot, kuluttajansuojan kertominen ja väärennösten torjunta.

---

## 0. What Malvoya has today (from the code, 18 Oct 2026)

- `Product` (backend/prisma/schema.prisma): free-text `category`, `condition`, `tags`, `gtin`, flags `isEcoFriendly`, `isHandmade`, `isSecondHand`. `ProductVariant` (the options): `size`, `color`, `sku`, `stock`, `priceAdjustCents`. No materials, ingredients, content, manufacturer, warnings or hygiene data.
- `Store`: `sellerType` BUSINESS/PRIVATE (shown to shoppers), `businessId`, `category` incl. `ECO_FRIENDLY`, `isEcoFriendly`.
- Search (`products.schema.ts`, `products.service.ts`): `eco=true` filter on `isEcoFriendly`.
- Customer app: `product_detail.dart` shows the chip "Eco-friendly / Ympäristöystävällinen", a generic hard-coded EU size table, and "Seller information" (DSA Art. 30 trader details, consumer-rights note for private sellers). `catalogue.dart` has the "Eco-friendly / Ekologinen" chip; `home.dart` has an "Eco-Friendly" shelf tile with a leaf icon in green, plus "Home" and "Returns" tiles.
- Store app: `product_editor.dart` has an "Eco-friendly / Ympäristöystävällinen" switch; `store_setup.dart` offers category "Eco-friendly / Ekologinen".
- Returns: 14 days from `deliveredAt` for all orders, no per-product exceptions, no hygiene handling. No product-level "report" button (reports exist for drops, comments and reviews). No recall flow.
- Omnibus "was" prices and verified reviews are already handled (CLAUDE.md).

---

## 1. General Product Safety Regulation (EU) 2023/988 ("GPSR")

Applies since 13 Dec 2024 (Art. 52). In Finland it is supplemented by the Act on the Safety of Consumer Products (laki kuluttajatuotteiden turvallisuudesta 184/2025, in force 5 May 2025), enforced by **Tukes**, which can impose a penalty fee (seuraamusmaksu) of up to 1 % of turnover (max. €100 000 for companies, €10 000 for individuals) on manufacturers, importers, distributors, authorised representatives **and online marketplace providers** for intentional or negligent GPSR breaches (Tukes news, 6 May 2025).

Scope notes that matter for Malvoya:
- GPSR covers all consumer products made available "in the course of a commercial activity", **including second-hand products** sold by businesses (recital 49). Antiques/collectors' items of historical significance are excluded (Art. 2(2), 3(30)). Private people selling their own used items occasionally are not "economic operators", but Malvoya's marketplace duties (Art. 22) still cover what is offered on Malvoya.
- **Cosmetics, textiles and sunglasses are covered by their own EU law for the risks those laws cover, but GPSR Chapter III Section 2 (Art. 19–21) and Chapter IV (Art. 22) still apply to them** (Art. 2(1): only Chapter II, Chapter III Section 1, V, VII, IX–XI are disapplied for harmonised products). So the Art. 19 listing information and Art. 22 marketplace duties apply to every product category Malvoya sells.

### 1.1 What a listing must show (Art. 19, mirrored for marketplaces in Art. 22(9))

The offer must "clearly and visibly" show at least:
- (a) the **manufacturer's** name, registered trade name or trade mark, and the postal **and** electronic address where it can be contacted;
- (b) **where the manufacturer is not established in the EU**, the name, postal and electronic address of the **EU responsible person** (Art. 16(1) GPSR / Art. 4(1) of Reg. 2019/1020: importer, authorised representative or fulfilment service provider);
- (c) information identifying the product, **including a picture, its type and any other product identifier**;
- (d) any **warning or safety information** that has to be on the product, its packaging or an accompanying document, in a language easily understood by consumers as set by the Member State. Tukes requires instructions and safety information in **Finnish and Swedish**.

Note on batch and serial numbers: the duty to put a "type, batch or serial number" **on the product** is the manufacturer's (Art. 9(5)). The listing must show the type and "any other product identifier" (Art. 19(c)); a batch number is not a listing requirement, but recall notices must identify batches (Art. 36(2)(b)(ii)), so Malvoya should capture GTIN and, where a shop sells a known batch, the batch.

### 1.2 Malvoya must (Art. 22)

1. **Two single contact points**: one for market surveillance authorities (electronic, for orders under Art. 22(4)), and **registration on the Safety Gate Portal** with that contact's details (Art. 22(1)); one for consumers on product safety (Art. 22(2)). Suggested: a product-safety address `[PLACEHOLDER: tuoteturvallisuus@…]` and an in-app "Tuoteturvallisuus / Product safety" contact form.
2. **Internal product-safety processes** (Art. 22(3)), including the mechanisms for traders to give the Art. 19 information and their **self-certification** that they only offer compliant products (Art. 22(10)).
3. **Interface design** that lets traders give the Art. 19 information for each product and shows it on the listing (Art. 22(9)).
4. **Authority orders** to remove a listing, disable access or show a warning: act **within two working days** and report back (Art. 22(4)); orders may cover all identical listings (Art. 22(5)).
5. **Safety Gate**: take into account the dangerous-product alerts on the Safety Gate Portal in Malvoya's own checks (Art. 22(6)); use at least the Safety Gate Portal for the DSA Art. 31(3) random checks (Art. 22(7)).
6. **Notices** about product safety (from anyone, through the DSA Art. 16 notice mechanism): process **within three working days** (Art. 22(8)).
7. **Repeat offenders**: suspend, after a prior warning, traders who frequently offer non-compliant products (Art. 22(11)).
8. **Cooperation and recalls** (Art. 22(12)): directly notify all affected consumers who bought through Malvoya when there is a recall or safety warning Malvoya knows about; publish recalls in the interface; tell the trader when a listing is removed; not obstruct recalls; immediately inform authorities through the **Safety Business Gateway** about dangerous products Malvoya knows were offered; pass on and notify accidents with serious risk or actual damage; allow authorities' online tools access; help trace supply chains.

### 1.3 The shop must

- As **distributor** (selling a brand's goods): check that the product bears the manufacturer details, identifier and Finnish/Swedish instructions and safety information before offering it; not sell products it knows or should know are dangerous; pass on accidents and safety issues to the manufacturer; cooperate in recalls.
- As **manufacturer** (own brand, handmade, or relabelled under its own name): everything in Art. 9 (risk analysis, technical documentation kept 10 years, identifier on the product, its own name and addresses on the product, instructions and safety info in FI/SV, corrective action and Safety Business Gateway notification).
- Give Malvoya the Art. 19 information per product and keep it accurate.

### 1.4 Product page needs

A "**Tuoteturvallisuus ja valmistaja / Product safety & manufacturer**" section on every product (Spec §5.1 item 3): manufacturer, EU responsible person when relevant, model/type, EAN, warnings (FI | SV | EN), label photos. The product picture is already there. Strong warnings also appear above the buy bar. A "**Ilmoita tuotteesta / Report this product**" action.

### 1.5 Store editor needs

Reusable manufacturer and responsible-person records; the EU responsible-person field appears only when the manufacturer is outside the EU/EEA; warnings as FI and SV text with an explicit "no warnings on the label" choice; GTIN; the one-time self-certification at onboarding with timestamp and terms version (stored like `termsAcceptedAt`). Publishing is blocked until the Art. 19 fields are complete (business sellers).

### 1.6 Recall flow (how to build it)

Data (Spec §6): `ProductSafetyCase {id, type: RECALL | SAFETY_WARNING | LISTING_REMOVAL, source: SAFETY_GATE | TUKES_ORDER | MANUFACTURER | SHOP | CONSUMER_NOTICE | MALVOYA_CHECK, sourceRef (Safety Gate alert no., order no.), match: {productIds, variantIds, gtin[], brand, model, batches[]}, hazard {fi, sv, en}, consumerAction {fi, sv, en}, remedies [repair | replacement | refund], contact (free phone or online service), status, openedAt, triagedAt, listingsDisabledAt, buyersNotifiedAt, authorityNotifiedAt, closedAt}` and `SafetyNotification {caseId, userId, orderItemId, channel push|email|in_app, sentAt, openedAt}`.

Steps:
1. **Intake** from: authority orders (to the authority contact point), Safety Gate matches (weekly automated match of GTIN, brand + model against Safety Gate alerts and Tukes' list of dangerous products, then a human check), manufacturer/shop recall announcements, consumer notices ("Report this product").
2. **Triage** the same or next working day; authority orders are done **within 2 working days**, notices **within 3 working days**.
3. **Disable** the listing (a locked "recalled" state the shop cannot switch back on) and all identical listings across shops (same GTIN, or same brand + model); add the identifiers to a blocklist so they cannot be re-listed or re-imported. Tell the shop with a statement of reasons (DSA Art. 17), as Malvoya already does for drops.
4. **Find buyers**: every `OrderItem` matching the case (product/variant, or GTIN/batch snapshot), **for all time Malvoya holds order records** (GPSR asks for "all affected consumers that can be identified"; the DSA Art. 32 six-month limit is for illegal products generally, not recalls). Accounts that were deleted are anonymised and cannot be contacted: those are covered by step 6.
5. **Notify directly** by push, email and an in-app notice. This is a legal obligation (GDPR Art. 6(1)(c)), so it is sent even to customers who switched off marketing. The written notice must follow Art. 36: headline "**Tuotteen turvallisuuteen liittyvä takaisinveto / Product safety recall**" (and the Swedish equivalent); picture, name and brand; identification numbers (batch/serial) and where to find them; when, where and by whom it was sold; a clear description of the hazard **without** softening words ("voluntary", "precautionary", "in rare cases", "no accidents reported"); what to do, starting with "stop using it now"; the remedies; a free phone number or online service; encouragement to share. Use the Commission's recall-notice template under Art. 36(3) (Tukes news, 13 Aug 2024).
6. **Publish** the recall on an in-app "Takaisinvedot / Recalls" page and a public web page, and as a banner on the product for anyone who opens it from an order (Art. 22(12)(a)(ii), 35(4)).
7. **Notify authorities** through the Safety Business Gateway about a dangerous product offered on Malvoya (Art. 22(12)(d)), with the risk details, quantities and measures taken.
8. **Remedy**: the economic operator responsible for the recall must offer at least two of repair, replacement or refund, cost-free (Art. 37). Malvoya can make this easy: a one-tap free courier pickup or "return to the shop", refund through Stripe on the shop's behalf with the shop payout adjusted (the existing `adjustStorePayoutForRefund`). The shop terms must give Malvoya this right *(verify in `legal/vendor_terms.md`)*.
9. **Track and close**: who opened the notice, reminder after 7 days to those who did not, report to the authority, close the case.

Admin panel: "Tuoteturvallisuus / Product safety" queue (cases, notices, Safety Gate matches) with the timers (2 and 3 working days) shown, in the style of the existing Moderation pages.

**Yhteenveto suomeksi.** Yleinen tuoteturvallisuusasetus (EU) 2023/988 on sovellettu 13.12.2024 alkaen, ja Suomessa sitä täydentää laki kuluttajatuotteiden turvallisuudesta (184/2025). Valvoja on Tukes, joka voi määrätä myös verkkomarkkinapaikalle seuraamusmaksun. Jokaisessa tuotteessa on näytettävä valmistajan nimi, posti- ja sähköpostiosoite, EU:n ulkopuolisen valmistajan EU-vastuuhenkilö, tuotteen kuva, tyyppi ja tunniste sekä varoitukset ja turvallisuustiedot suomeksi ja ruotsiksi. Malvoyan on nimettävä yhteyspisteet viranomaisille (rekisteröinti Safety Gate -portaaliin) ja kuluttajille, käsiteltävä viranomaisen määräykset kahdessa ja turvallisuusilmoitukset kolmessa työpäivässä, seurattava Safety Gate -hälytyksiä, keskeytettävä toistuvasti vaarallisia tuotteita tarjoavat myyjät ja ilmoitettava takaisinvedoista suoraan jokaiselle ostajalle. Kauppa vastaa jakelijana tai valmistajana tuotteen turvallisuudesta ja tietojen oikeellisuudesta.

---

## 2. Textile Labelling Regulation (EU) No 1007/2011

Applies to textile products and to products with at least 80 % textile fibres by weight (Art. 2), so clothing, most textile accessories (scarves, hats, gloves), canvas bags, and textile parts of some other products.

Rules:
- Only the fibre names in **Annex I** may describe fibre composition (Art. 5). Composition is given by **name and percentage by weight, in descending order** (Art. 9(1)); "other fibres" is allowed only for fibres up to 5 % (or several up to 15 %) that are hard to state at manufacture, or not yet listed (Art. 9(2), (5)). "100 %", "pure", "all" only for products of one fibre (Art. 7). Multi-component products state each component; components that are not main linings and are under 30 % of the weight may be left out (Art. 11).
- "**Contains non-textile parts of animal origin**" / "**Sisältää muuta kuin tekstiiliä olevia eläinperäisiä osia**" must be shown when such parts are present (Art. 12), e.g. leather patches, fur trims, horn buttons.
- When a textile is made available, the composition "shall be **clearly visible to the consumer before the purchase, including in cases where the purchase is made by electronic means**", legibly and in uniform print; brand names may stand next to it, other information separately (Art. 16(1)–(2)).
- Language: the official language(s) of the Member State (Art. 16(3)); Tukes says mandatory consumer information is required in **Finnish and Swedish**.
- Fibre names in English and Finnish: Spec §2.2 table (from the EN and FI texts of Annex I).

**Malvoya must** design the interface so the composition can be given in the legal format and is shown before purchase (this is also the DSA Art. 31 / GPSR Art. 22(9) "compliance by design" duty). Offer only Annex I names, enforce 100 % per component, show composition near the price.

**The shop must** copy the composition from the product's label (as distributor it must make sure the label exists, Art. 15(3)); if it puts its own brand on the product or changes the label, it becomes the manufacturer for labelling purposes (Art. 15(2)).

**Product page needs** a Materials block above the fold (Spec §5.1 item 4). **Store editor needs** the composition builder (Spec §5.2 item 3). Private second-hand sellers may state "label missing"; the page then says so.

**Yhteenveto suomeksi.** Tekstiilituotteen kuitukoostumus on ilmoitettava asetuksen liitteen I nimityksillä, painoprosentteina suurimmasta pienimpään, ja sen on näyttävä kuluttajalle ennen ostoa myös verkossa. Monikomponenttituotteissa (esim. vuori) jokainen osa ilmoitetaan erikseen. Eläinperäiset ei-tekstiiliosat ilmoitetaan ilmauksella "sisältää muuta kuin tekstiiliä olevia eläinperäisiä osia". Tukesin mukaan pakolliset kuluttajatiedot annetaan suomeksi ja ruotsiksi. Malvoya tarjoaa vain sallitut kuitunimet ja tarkistaa, että prosentit ovat yhteensä 100; kauppa kopioi tiedot tuotteen etiketistä.

---

## 3. Cosmetics Regulation (EC) No 1223/2009

### 3.1 What the pack must carry (Art. 19) and what the buyer must see online

The pack must show: (a) name and address of the **responsible person** (and country of origin for imports); (b) **nominal content** by weight or volume (not for packs under 5 g/5 ml, free samples, single-application packs); (c) **date of minimum durability** ("best used before the end of" / hourglass symbol) for products lasting 30 months or less, otherwise the **period after opening** (open-jar symbol with months); (d) **particular precautions**, at least those in Annexes III–VI; (e) **batch number** or reference; (f) **function**, unless clear; (g) **ingredient list** headed "Ingredients", in descending order of weight (under 1 % in any order), with common ingredient (INCI) names from the glossary (Art. 19(6)), "parfum"/"aroma" for perfume, Annex III fragrance allergens named, "(nano)" after nanomaterials, colorants with CI numbers and "may contain"/"+/-" for shade ranges.

Language (Art. 19(5) and Tukes): in Finland, **content, minimum durability, precautions, function (and instructions) in Finnish and Swedish**. INCI names are international.

The Cosmetics Regulation itself does not list online display duties. The duty to show these facts **before an online purchase** comes from:
- the Consumer Protection Act ch. 6 §9 and the Consumer Rights Directive Art. 6(1)(a): the **main characteristics** of the goods must be given before the contract (for cosmetics, buyers with allergies cannot judge a product without the ingredient list);
- GPSR Art. 19(d): **warnings and safety information** (= the Art. 19(1)(d) precautions) must be on the listing in Finnish/Swedish;
- GPSR Art. 19(a)/(b): the manufacturer / EU contact (for cosmetics usually the responsible person).

Malvoya's rule (REQUIRED-BY-MALVOYA in the spec): the listing shows ingredients (INCI), content, PAO or best-before, function, how to use, precautions and the responsible person's name and address. This matches what Tukes asks shoppers to check before buying ("read the label before you buy") and what the major Nordic beauty shops display.

### 3.2 Malvoya must

- Provide the fields and show them (Spec §2.7) and block publishing without them.
- Run the **distributor-style checks** for the products on its interface as part of its GPSR internal process: the responsible person, ingredients and the Finnish/Swedish language items are present, the best-before date has not passed (these are the checks Art. 6(2) puts on distributors; a marketplace is not the distributor, but making them a publishing rule is the practical way to meet GPSR Art. 22(3) and DSA Art. 31).
- Run the claims linter (Spec §2.14) and react to notices.
- **Not** check CPNP notification itself: notifying the product to the Cosmetic Products Notification Portal before placing it on the market is the **responsible person's** duty (Art. 13). Malvoya may ask own-brand shops (who are responsible persons) to confirm it.

### 3.3 The shop must

- As distributor (Art. 6): verify before selling that the responsible person, ingredients, batch and Finnish/Swedish items are on the pack and that the date has not passed; not sell non-conforming products; report risks to the responsible person and authorities; store and transport properly.
- If it sells **under its own name** or modifies the product, it becomes the **responsible person** (Art. 4(6)): product information file, safety assessment, CPNP notification, labelling, claims evidence. Small Finnish own-brand makers (handmade soaps, balms) are responsible persons and must be told so in onboarding (link to Tukes guidance).
- Translating the label into Finnish/Swedish alone does not make a distributor the responsible person (Art. 4(6)), but distributors that translate on their own initiative must submit some information to the CPNP (Art. 13(3)).

### 3.4 Claims (Art. 20, Regulation (EU) No 655/2013, technical document)

- No text, name, picture or sign may imply characteristics the product does not have (Art. 20(1)). The six common criteria of Reg. 655/2013: legal compliance, truthfulness, evidential support, honesty, fairness, informed decision-making. The responsible person must have evidence in the product information file.
- **No medical claims.** A product presented as treating or preventing disease is a medicinal product (supervised in Finland by Fimea), not a cosmetic. The linter blocks words like "treats eczema", "acne treatment", "cures", "antibacterial" (Spec §2.14).
- **"Free from" and "hypoallergenic"**: the *Technical document on cosmetic claims* (version of 3 July 2017; its Annexes III and IV apply from 1 July 2019; non-binding guidance endorsed by the Commission-chaired Working Group, used by authorities) says, among other things: no "free from" a substance that is banned anyway; no "free from" a functional group if anything with that function is present (e.g. "preservative-free" with alcohol as preservative, "perfume-free" with an ingredient that perfumes); no denigrating claims such as "free from parabens" or "free from phenoxyethanol"; no "free from allergens"; allowed where they help a target group decide, such as "alcohol-free", "free from animal-derived ingredients", "acetone-free" nail polish. "Hypoallergenic" only for products designed to minimise allergenic potential, with robust evidence and no known sensitisers. Claims that present mere legal compliance as a benefit are not allowed. Malvoya implements this as a short list of validated free-from values (Spec §2.7.1).
- **Vegan / cruelty-free**: animal testing for cosmetics is banned in the EU (Art. 18), and Art. 20(3) restricts "not tested on animals" claims; on its own such a claim presents a legal requirement as a special feature (also banned by Directive 2024/825 Annex I point 10a for all products). Malvoya therefore offers these only as **certified** claims (Leaping Bunny, The Vegan Society trademark and similar) with the licence shown (Spec §2.12). "Vegan" as a factual "free from animal-derived ingredients" is allowed through the validated free-from value.

### 3.5 Upcoming: fragrance allergens

Regulation (EU) 2023/1545 expanded the list of fragrance allergens that must be named on labels. Products not complying could be **placed** on the market until 31 July 2026 and may be **made available** until **31 July 2028**. Shops' INCI lists will change; Malvoya's allergen finder must use the updated Annex III list.

### 3.6 Product page needs / Store editor needs

Page: ingredient panel with search, content and unit price, PAO/best-before, function, how to use, precautions, responsible person, hygiene-seal badge (Spec §5.1 items 2, 5, 6). Editor: COSMETIC template, INCI paste box with validation, shade table, free-from validation, best-before per stock lot that hides expired options (Spec §5.2).

### 3.7 Malvoya rules for second-hand and private sellers of beauty

- Only **sealed, unused, in-date** cosmetics and fragrances; no testers or samples marked "not for sale"; no professional-use-only products.
- At launch, beauty only from **business sellers** (a private person's sealed lipstick still has to meet labelling rules the person cannot check, and there is no withdrawal right). Revisit later.

**Yhteenveto suomeksi.** Kosmetiikkapakkauksessa on oltava vastuuhenkilön nimi ja osoite, nimellissisältö, vähimmäissäilyvyysaika tai avaamisen jälkeinen käyttöaika, varotoimet, eränumero, käyttötarkoitus ja INCI-ainesosaluettelo; sisältö, säilyvyys, varotoimet ja käyttötarkoitus suomeksi ja ruotsiksi. Verkossa nämä tiedot näytetään ennen ostoa (keskeiset ominaisuudet ja GPSR:n varoitukset), ja Malvoya tekee niistä julkaisun edellytyksen. CPNP-ilmoitus on vastuuhenkilön velvollisuus, ei Malvoyan. Omalla nimellään myyvä kauppa on itse vastuuhenkilö. Väitteiden on oltava totuudenmukaisia ja näytöllä tuettuja (asetus 655/2013); lääkkeellisiä väitteitä ei saa käyttää. "Ei sisällä" -väitteet rajataan sallittuihin (esim. alkoholiton, hajusteeton tarkistettuna), ja vegaani- ja eläinkokeettomuusväitteet vain sertifikaatilla. Laajennettu hajusteallergeeniluettelo koskee kaikkia myytäviä tuotteita 31.7.2028 alkaen. Käytettyä tai avattua kosmetiikkaa ei myydä.

---

## 4. Unit prices: Price Indication Directive 98/6/EC and Finnish decree 553/2013

- The directive requires the selling price **and the unit price** for products offered to consumers; the unit price is per kilogram, litre, metre, m² or m³, or another unit "widely and customarily used in the Member State" (Art. 2(b), 3). It need not be shown when it equals the selling price.
- **Finland did not choose 100 g / 100 ml.** Valtioneuvoston asetus kulutushyödykkeen hinnan ilmoittamisesta markkinoinnissa (553/2013) §3: the unit price is given "kilo-, litra-, metri-, neliömetri- tai kuutiometrihintana". §4: goods offered **on websites** must show the selling and unit price, the unit price distinguishable from the selling price, large enough and easy to notice. §10: for non-food goods, no unit price is needed for (1) single items whose content cannot be divided without changing them, and (2) **pre-packages with less than 50 g or 50 ml**. The KKV guideline confirms: price per kilo, "not for example per 100 grams", and the same rules during sales.
- So: a 30 ml serum needs no unit price; a 50 ml cream, a 200 ml shampoo, a 100 ml perfume do. A lipstick (typically 3–4 g) does not.

**Malvoya must** compute and show it (the shop gives only content per option): `€/l` for ml, `€/kg` for g, two decimals, Finnish formatting (`1 780,00 €/l`), on product pages, tiles where a price is shown, and in search results sorted by unit price; recalculated for reduced prices. **The shop must** give the correct nominal content per option.

**Product page needs** the unit price line under the price (Spec §5.1 item 2). **Editor needs** a content field per option with live preview.

**Yhteenveto suomeksi.** Hinnan lisäksi on ilmoitettava yksikköhinta, Suomessa kilo- tai litrahintana (ei 100 g tai 100 ml) – myös verkkokaupassa ja alennushinnoissa. Yksikköhintaa ei tarvita alle 50 g tai 50 ml valmispakkauksille. Kauppa antaa sisällön jokaiselle vaihtoehdolle, ja Malvoya laskee ja näyttää yksikköhinnan hinnan alla.

---

## 5. Green claims: Directive (EU) 2024/825 ("Empowering Consumers for the Green Transition") — and Malvoya's "eco" flag

### 5.1 The law

Directive 2024/825 amended the Unfair Commercial Practices Directive. Member States had to apply it **from 27 Sept 2026**. Finland did so by **Act 573/2026 (26.6.2026)** amending the Consumer Protection Act (e.g. new ch. 2 §6 a, §6 b, §8 f; the blacklist is in the government decree on unfair practices). The Consumer Ombudsman (KKV) supervises; its updated guideline on responsibility and environmental claims is out for comments until 21 Oct 2026.

Definitions (Art. 2(o)–(s) UCPD as amended): an **environmental claim** is any non-mandatory message or representation, in any form, **including text, pictures, graphics, symbols, labels, brand names, company names or product names**, stating or implying a positive or reduced environmental impact. A **generic environmental claim** is one whose specification is not given clearly and prominently on the same medium. A **sustainability label** is a voluntary trust or quality mark about environmental or social characteristics. A **certification scheme** is third-party verified, open to all traders, developed with stakeholders, with sanctions for non-compliance. **Recognised excellent environmental performance** means the EU Ecolabel, an officially recognised EN ISO 14024 type I ecolabel (e.g. the Nordic Swan), or top performance under other EU law.

Always banned (UCPD Annex I, new points):
- **2a** displaying a sustainability label not based on a certification scheme or not set by public authorities;
- **4a** making a generic environmental claim when the trader cannot show recognised excellent environmental performance relevant to the claim (the recital's examples: "environmentally friendly", "eco-friendly", "green", "nature's friend", "ecological", "climate friendly", "biodegradable"; "sustainable", "conscious" and "responsible" cannot rest on environmental performance alone because they also imply social qualities);
- **4b** a claim about the whole product or the whole business when it concerns only part of it;
- **4c** carbon-neutral claims based on offsetting;
- **10a** presenting legal requirements as a distinctive feature.

KKV's draft guideline adds two points that matter for an app: the specification of a claim must be on the same medium, clearly visible, and **cannot be behind a link or QR code**; and colours, pictures and other visual elements combined with words can make a generic claim. A mark that only tells the origin (e.g. Finnish origin) is not a sustainability label.

Transition: KKV and the Finnish Entrepreneurs report that claims on **goods or packaging already placed on the market before 27 Sept 2026** get until **27 March 2027**. This does **not** help Malvoya's own interface: the chip, filter and tile are Malvoya's current commercial communications.

### 5.2 Exactly what is wrong with Malvoya's "eco" flag

| Where | What it does | Why it breaks the rules |
|---|---|---|
| `Product.isEcoFriendly` (schema), `isEcoFriendly` in `products.schema.ts`, set by a switch "Eco-friendly / Ympäristöystävällinen" in `malvoya_vendor/.../product_editor.dart` | Any seller can tick it, with no evidence and no definition | The resulting claim is generic (no specification), not tied to the EU Ecolabel or a type I ecolabel: **Annex I 4a**. It usually concerns only one aspect (e.g. organic cotton shell): **4b**. |
| Product chip "Eco-friendly / Ympäristöystävällinen" (mint background, green text) in `product_detail.dart` | Malvoya displays the claim as a badge | Malvoya itself makes the claim; a badge also works like a self-made **sustainability label** not based on certification: **2a**. Colour reinforces it. |
| Search filter `eco=true` (`products.service.ts`), catalogue chip "Eco-friendly / Ekologinen" (`catalogue.dart`) | Malvoya groups products as "ecological" | Same generic claim, made by Malvoya as a selling point of the marketplace. |
| Home shelf tile "Eco-Friendly" with `Icons.eco_outlined` (leaf) on mint/emerald (`home.dart`), category label "Ekoystävällinen" (`l10n.dart`), `CategoryDetailScreen` case | Malvoya advertises a whole "eco" collection | Generic claim plus imagery; and a claim about a group of products when only some aspects (if any) qualify: **4a, 4b**. |
| `StoreCategory.ECO_FRIENDLY` ("Eco-friendly / Ekologinen" in `store_setup.dart`, green badge in admin `Vendors.tsx`), `Store.isEcoFriendly` | A shop can call its whole business eco | A generic claim about the **trader's entire business**: **4a, 4b**. |
| `Product.tags` (schema comment "eco-friendly"), Shopify/WooCommerce tags imported as-is | Tags like "eco" or "sustainable" become searchable | Search hits for "eco" present those products as eco. Lower risk (tags are not displayed), but clean them. |

Being pre-launch does not change the analysis: the builds exist and must not reach the public with these claims.

### 5.3 The fix

1. **Remove now** (one release): the product switch, product chip, catalogue chip and `eco` search parameter, the Home "Eco-Friendly" tile and its category route and translations, `StoreCategory.ECO_FRIENDLY` and `Store.isEcoFriendly` (migrate those stores to OTHER and ask them to choose), and stop returning `isEcoFriendly` from the API (drop the columns in a later migration). Also stop importing tags that are generic green words (run them through the claims linter).
2. **Replace with specific, verifiable attributes** (Spec §2.12, §2.13):
   - **Second-hand / Käytetty** (already `isSecondHand`): a fact, not an environmental claim. Do not add copy such as "kestävä valinta / sustainable choice" next to it.
   - **Certified: [scheme]** chips only from verified `ProductCertification` records with licence number, holder, scope and expiry shown on the page: EU Ecolabel (EU-ympäristömerkki), Nordic Swan (Joutsenmerkki), GOTS, Fairtrade (Reilu kauppa), and others after an admin checks the scheme meets the definition. A generic word like "ympäristömerkitty" may appear only for EU Ecolabel / Nordic Swan products and only within what their criteria cover.
   - **Specific material facts** with evidence: "Sisältää 60 % kierrätettyä polyesteriä (GRS) / Contains 60 % recycled polyester (GRS)", "Luomupuuvillaa 100 % (GOTS)".
   - **Made in Finland / Valmistettu Suomessa** (`countryOfManufacture = FI`; optionally the Avainlippu licence): an origin fact, not a sustainability label, but it must be true.
   - **Handmade / Käsintehty**: a fact.
3. **Word the filters honestly.** In catalogue "All filters", a section "**Ominaisuudet / Attributes**" with chips "Käytetty / Second-hand", "Valmistettu Suomessa / Made in Finland", "Käsintehty / Handmade", and a section "**Sertifikaatit / Certificates**" listing scheme names ("Joutsenmerkki", "EU-ympäristömerkki", "GOTS", "Reilu kauppa") with counts. No umbrella label like "Eko", "Vastuullinen", "Kestävä" or "Vihreä", no leaf icon, no green colour coding.
4. **Home**: replace the Eco tile with "Valmistettu Suomessa / Made in Finland" or "Sertifioidut tuotteet / Certified products" once such stock exists; until then, show the second-hand collection.
5. **Seller terms**: forbid generic environmental claims and uncertified sustainability labels in listings, and require evidence on request (add to `legal/vendor_terms.md`).

**Yhteenveto suomeksi.** Vihreän siirtymän direktiivi (EU) 2024/825 pantiin Suomessa täytäntöön lailla 573/2026, ja sitä sovelletaan 27.9.2026 alkaen. Yleiset ympäristöväittämät (esim. "ympäristöystävällinen", "ekologinen", "vihreä") ovat kiellettyjä, ellei tunnustettua erinomaista ympäristönsuojelun tasoa (EU-ympäristömerkki, Joutsenmerkki) voida osoittaa. Kiellettyjä ovat myös muut kuin sertifiointiin perustuvat tai viranomaisen vahvistamat kestävyysmerkinnät sekä koko tuotetta tai yritystä koskevat väitteet, kun ne koskevat vain osaa. Täsmennys on esitettävä samassa näkymässä, ei linkin takana. Malvoyan "Eco-friendly/Ekologinen/Ympäristöystävällinen"-kytkin, -merkki, -suodatin, etusivun lehtikuvalla varustettu ruutu ja kauppakategoria ECO_FRIENDLY ovat juuri tällaisia yleisiä väittämiä, eikä myyjän valintaa tarkisteta. Ne poistetaan, ja tilalle tulevat todennettavat tiedot: käytetty, sertifikaatti (järjestelmä, lisenssinumero, kattavuus, voimassaolo), kierrätysmateriaalin osuus näytön kanssa, valmistettu Suomessa ja käsintehty. Suodattimien otsikot ovat "Ominaisuudet" ja "Sertifikaatit", ei "Eko" tai "Vastuullinen".

---

## 6. Hygiene exception to the 14-day right of withdrawal

**Law.** Consumer Rights Directive 2011/83/EU Art. 16(e); Consumer Protection Act ch. 6 §16 ("Peruuttamisoikeuden rajoitukset"): unless agreed otherwise, there is no right of withdrawal when "sinetöitynä toimitettu tavara, jota ei terveydellisistä tai hygieniasyistä voida palauttaa, on avattu" (sealed goods that cannot be returned for health or hygiene reasons have been unsealed after delivery). Before the contract the consumer must be told when there is no right of withdrawal **or the circumstances in which it is lost** (Art. 6(1)(k) CRD; ch. 6 §9), and this is confirmed in the order confirmation (ch. 6 §13). If the seller fails to inform, the exception is hard to rely on.

**How narrow it is.** The Commission's CRD guidance (2021/C 525/01, §5.11.4) says there must be genuine health or hygiene reasons for the seal (protective wrapping or film may qualify) and gives as examples **cosmetic products such as lipsticks** and **toothbrushes, shavers and similar personal hygiene items**. In **C-681/17 slewo** (27 March 2019) the CJEU held that a mattress whose protective film was removed can still be returned, likening it to a **garment** that the trader can clean; the exception applies only if, once unsealed, the goods are definitively unsaleable for health or hygiene reasons because their nature makes cleaning for resale impossible or excessively difficult.

What that means for Malvoya's categories:
- **Apply** to: cosmetics, skincare, haircare, fragrance in a sealed state (cellophane, sealed cap/foil, sealed box); piercing jewellery and earrings sold in sealed hygienic packs (an inference from the guidance's personal-hygiene examples; *verify*).
- **Do not apply** to clothing in general, including underwear and swimwear: after *slewo* a hygiene liner or sticker does not by itself remove the withdrawal right. Instead use the normal rule that the consumer is liable for diminished value from handling beyond what is needed to establish the goods' nature (CRD Art. 14(2); ch. 6 §18): e.g. swimwear tried on over underwear with the liner intact is returnable; visibly worn items can carry a deduction (the existing `damageDedCents`/`storeNote`).
- Private sellers: no statutory withdrawal right at all (§7).

**Malvoya must** show the exception before purchase and in the confirmation, and make the returns flow consistent with it. **The shop must** mark sealed products correctly and only rely on the exception when the seal was really broken.

**Product page needs** the returns badge (Spec §5.1 item 6): "Hygieniasinetöity – ei palautusoikeutta, jos sinetti avataan. Avaamattoman tuotteen voit palauttaa 14 päivän kuluessa. / Hygiene seal — can't be returned once the seal is opened. Unopened, you can return it within 14 days." Same line in the bag and checkout; the order confirmation email lists which items are hygiene-sealed.

**Returns flow** (backend `createReturn`, customer `returns_screen.dart`):
1. `OrderItem.hygieneSeal` is snapshotted at purchase (the product can change later).
2. When the customer selects a hygiene-sealed item with reason "changed my mind", the app asks "Onko sinetti ehjä? / Is the seal unbroken?". Yes → normal return, with a reminder to keep it sealed. No → explain that the item can't be returned for that reason, and offer the routes that always remain: wrong item, damaged on arrival, not as described (faults are covered by the seller's liability for defects under ch. 5, not by the withdrawal right).
3. The shop inspects on receipt; if the seal is broken it may reject with `storeNote` and a photo; the customer sees it and can contact support.
4. Malvoya never applies the exception automatically to apparel.

**Yhteenveto suomeksi.** Peruuttamisoikeutta ei ole, jos sinetöitynä toimitettu tavara, jota ei terveys- tai hygieniasyistä voida palauttaa, on avattu (KSL 6:16; direktiivin 16 e artikla). Asiasta on kerrottava ennen ostoa ja tilausvahvistuksessa. Komission ohjeen esimerkkejä ovat huulipunat ja hammasharjat; EU-tuomioistuimen patja-asiassa (C-681/17) poikkeusta tulkittiin suppeasti ja verrattiin vaatteisiin, jotka voidaan puhdistaa. Malvoya soveltaa poikkeusta vain sinetöityyn kosmetiikkaan, tuoksuihin ja hygieniapakattuihin lävistys- ja korvakoruihin, ei vaatteisiin (myöskään alus- tai uima-asuihin). Tuotesivulla ja kassalla näytetään hygieniasinettimerkintä, ja palautuksessa kysytään, onko sinetti ehjä. Virheellisen tuotteen palautus on aina mahdollista.

---

## 7. Second-hand goods, private sellers, counterfeits, trader information (DSA Art. 30–32)

**Private sellers.** Consumer rights (withdrawal, the seller's liability for defects under the Consumer Protection Act) apply only when the seller is a business. The marketplace must tell consumers whether the third party offering the goods is a trader, and if not, that consumer-protection rights do not apply (Consumer Protection Act ch. 6 §9 a, from the Omnibus Directive). Malvoya already models `sellerType` and shows it with the right explanation in "Seller information"; keep it on every product page and in checkout, and keep `sellerType` locked after verification. A private person who sells regularly for profit is a trader: watch volume (Malvoya already has DAC7 data) and reclassify.

**Second-hand condition.** Describe condition and defects honestly (KKV's campaign on second-hand online shops found gaps). Use the condition scale, defects note and defect photos in Spec §2.13. Second-hand children's clothing with hood/neck drawstrings and jewellery with lead or cadmium are still unsafe products (§8).

**Counterfeits.** Brand-name items, especially second-hand luxury bags, watches, designer clothing and sneakers, carry counterfeit risk. Malvoya must: provide a notice-and-action route for anyone, including right holders ("Report this product" → reason "Counterfeit"), act on notices diligently and give statements of reasons (DSA Art. 16, 17 — these apply regardless of size); suspend repeat infringers after a warning (DSA Art. 23); and, as a Malvoya rule, require an authenticity basis for high-risk brands (Spec §2.13) and hold such listings for admin review. Selling counterfeits is also a trade mark infringement and can be a crime; Customs (Tulli) intercepts imports.

**DSA Art. 30–32.** Art. 30 (trader traceability: name, address, phone, email, ID, payment account, trade register number, self-certification; checked with best efforts; the name, address and register number shown on the product page), Art. 31 (compliance by design: the interface lets traders give pre-contractual, compliance and product-safety information, product identification, trade marks and labelling information; best-efforts checks before allowing products; random checks against official databases of illegal products) and Art. 32 (inform buyers of illegal products bought in the last 6 months, or publish the information). **Note:** DSA Art. 29 excludes these from platforms that are micro or small enterprises, which Malvoya is today. Malvoya should comply anyway because (a) GPSR Art. 22(9)–(10) imposes the product-safety parts of Art. 31 and the self-certification without any size exemption, (b) the Consumer Protection Act ch. 6 §9 a applies regardless of size, (c) much is already built (Seller information, Y-tunnus check against PRH/YTJ, Stripe KYC), and (d) the exemption ends 12 months after Malvoya stops being small.

**Malvoya must** keep and display trader information, run notice-and-action and suspensions, show business/private status. **The shop must** give truthful identity data, condition and authenticity information, and not sell counterfeits.

**Yhteenveto suomeksi.** Kuluttajansuoja (peruuttamisoikeus, virhevastuu) koskee vain yritysmyyjiä; markkinapaikan on kerrottava, onko myyjä elinkeinonharjoittaja, ja jos ei ole, ettei kuluttajansuojaa sovelleta (KSL 6:9 a). Malvoya tekee tämän jo; myyjätyyppi pidetään näkyvissä ja säännöllisesti voittoa tavoitteleva myyjä luokitellaan yritykseksi. Käytettyjen tuotteiden kunto ja viat kerrotaan rehellisesti kuvin. Väärennöksiä vastaan tarvitaan ilmoitusmekanismi, perustellut päätökset, toistuvien rikkojien keskeyttäminen ja merkkituotteille aitoustieto. DSA:n 30–32 artikla ei velvoita mikro- ja pienyrityksiä, mutta GPSR ja kuluttajansuojalaki vaativat samoja asioita ilman kokorajaa, joten Malvoya noudattaa niitä.

---

## 8. Children's clothing, jewellery metals, REACH SVHC right to know

**Children's clothing cords and drawstrings.** Under GPSR the product must be safe; conformity with the European standard EN 14682 (SFS-EN 14682) gives a presumption for this risk. Tukes summarises: clothing for children **under 7 or up to 134 cm** must have **no cords or drawstrings in the hood or head/neck area** and no cords tied behind the neck; for **7–14-year-olds** no free-hanging drawstring ends in the hood/neck area; long cords elsewhere (hems, legs) should be avoided. Fancy-dress costumes are toys and must meet toy rules. Tukes found such defects in cheap online shops and removed products from the market. **Malvoya must** add a cords declaration for kids' clothing, block listings declaring hood/neck cords for under-7s, spot-check photos, and treat second-hand kids' clothing the same. **The shop must** not sell non-compliant items (or remove the cords before sale).

**Jewellery and metal accessories (REACH Annex XVII).** Per Tukes: **nickel** (entry 27) — post assemblies inserted into pierced ears or other pierced parts must release less than **0.2 µg/cm²/week**; parts of items in direct and prolonged skin contact (earrings, necklaces, bracelets, rings, watch cases and straps, rivet buttons, zips and metal marks on garments) no more than **0.5 µg/cm²/week**, and a coating must keep release under the limit for at least two years of normal use; test method EN 1811 (total content tests like XRF do not prove compliance). **Cadmium** (entry 23) in jewellery and its metal and plastic parts: max **0.01 %** by weight. **Lead** (entry 63) in jewellery and parts: below **0.05 %** by weight. These apply to recycled materials and remade items too; there are carve-outs for older items placed on the market before the restrictions and for antiques (*verify the exact dates in Annex XVII before relying on them for second-hand jewellery*). **Malvoya must** ask for the basis of nickel safety for new jewellery and metal accessories and the lead/cadmium basis for non-precious jewellery (Spec §2.10), allow "Nikkelitön / Nickel-free" only with a test report or an inherently nickel-free material, and include these products in Safety Gate checks (cheap jewellery from outside the EU is a frequent Safety Gate and Tukes finding). **The shop must** buy from suppliers who give declarations or test reports.

**REACH Art. 33 "right to know".** A supplier of an **article** containing a Candidate List substance (SVHC) above 0.1 % by weight must, on a consumer's request, give enough information for safe use, at least the substance name, **free of charge within 45 days**, whether or not the person bought it (ECHA). It covers articles (clothes, shoes, bags, jewellery), **not mixtures such as cosmetics**. **Malvoya must** give consumers a way to ask (a "Kysy kemikaaleista / Ask about chemicals" option in the product's "…" menu that routes the question to the shop and records the 45-day deadline). **The shop must** answer (it is the supplier).

**Yhteenveto suomeksi.** Alle 7-vuotiaiden (enintään 134 cm) vaatteissa ei saa olla nyörejä hupussa tai pään ja kaulan alueella, eikä 7–14-vuotiaiden vaatteissa vapaasti roikkuvia nyörinpäitä (SFS-EN 14682, Tukes). Koruissa nikkelin vapautuminen saa olla lävistyskoruissa alle 0,2 ja muissa ihoa pitkään koskettavissa enintään 0,5 µg/cm²/viikko; kadmiumia enintään 0,01 % ja lyijyä alle 0,05 % painosta (REACH liite XVII). Malvoya pyytää perusteen nikkeliturvallisuudelle ja sallii "nikkelitön"-merkinnän vain testin tai materiaalin perusteella. REACH 33 artiklan mukaan kuluttaja saa kysyä erityistä huolta aiheuttavista aineista, ja toimittajan on vastattava maksutta 45 päivässä; Malvoya välittää kysymyksen kaupalle.

---

## 9. Footwear labelling (Directive 94/11/EC)

Footwear must be labelled with the material of its three parts — **upper, lining and insole (sock), outer sole** — as **leather, coated leather, textile or other**, by pictograms or words; if no material reaches 80 % of a part, the two main materials are given; the manufacturer (or the importer) supplies the label and the retailer makes sure it is there; written labels in the language(s) of the country (Your Europe, last checked 13 July 2026; Finland: Finnish and Swedish). The directive does not mention online sales, but these materials are main characteristics a shopper needs before buying (ch. 6 §9), so Malvoya makes the three material fields required for new footwear (Spec §2.4).

**Yhteenveto suomeksi.** Jalkineiden päällisen, vuorin ja sisäpohjan sekä ulkopohjan materiaali (nahka, pinnoitettu nahka, tekstiili tai muu) merkitään kenkään. Verkossa Malvoya näyttää nämä keskeisinä ominaisuuksina, ja ne ovat pakollisia uusille kengille.

---

## 10. Size labelling (EN 13402) — best practice, not law

There is no EU law requiring a size system. The European standard EN 13402 describes body-dimension based sizing (key dimensions in cm, e.g. chest/bust and height for tops, waist and inside leg for trousers, height for children). Best practice for Malvoya: every new clothing item has the shop's own **size chart in cm** (body or garment measurements, labelled which), shoes have foot length per EU size, second-hand items have measured garment dimensions. Replace today's generic hard-coded table on the product page: presenting a generic chart as if it were the item's could mislead (Consumer Protection Act ch. 2 §6). Spec §2.2, §5.1 item 8.

**Yhteenveto suomeksi.** Kokomerkinnät eivät ole lakisääteisiä, mutta standardin EN 13402 mukainen mitoitus senttimetreinä on hyvä käytäntö. Jokaiselle vaatteelle tulee kaupan oma kokotaulukko senttimetreinä, kengille jalan pituus ja käytetyille tuotteille mitatut mitat. Nykyinen yleinen kokotaulukko korvataan tuotteen omalla.

---

## 11. Out of scope or gated categories

Not covered by these templates; keep them off Malvoya until a separate review (the importer puts such drafts on hold, Spec §1.4):
- **Food supplements** (hair/skin vitamins, collagen drinks): food law, supervised by Ruokavirasto; not cosmetics.
- **Medicinal products and medical devices** (e.g. hair-loss treatments, products claiming to treat skin disease): Fimea.
- **Biocides** (hand sanitisers, disinfectants) and **CLP-classified chemicals** (nail glue, some removers that are not cosmetics): Tukes; hazard information must be shown online.
- **Electrical beauty tools** (hair dryers, straighteners, smart watches): electrical safety, radio equipment, WEEE and battery producer duties.
- **Toys**, including fancy-dress costumes.
- **Home décor and candles**: outside the product scope (see Spec §1.5).
- **Sunglasses** are allowed but are personal protective equipment (CE marking, UV category): admin-checked template (Spec §2.6), not analysed here.

**Yhteenveto suomeksi.** Ravintolisät (Ruokavirasto), lääkkeet ja lääkinnälliset laitteet (Fimea), biosidit ja CLP-luokitellut kemikaalit (Tukes), sähköiset kauneuslaitteet, lelut sekä sisustus ja kynttilät jätetään toistaiseksi pois. Aurinkolasit ovat henkilönsuojaimia ja tarkistetaan erikseen.

---

## 12. Sources (all read on 18 Oct 2026 unless marked)

EUR-Lex itself answered with a bot challenge, so the EU texts were read from the same Official Journal documents served by the Publications Office (publications.europa.eu, Cellar), which is the source EUR-Lex publishes. These are the **original** OJ texts; check the consolidated versions on EUR-Lex for later amendments (noted where known).

| Source | Used for | Read |
|---|---|---|
| Regulation (EU) 2023/988 (GPSR), OJ L 135, 23.5.2023 — http://data.europa.eu/eli/reg/2023/988/oj — Art. 2, 3, 9, 16, 19, 21, 22, 35, 36, 37, 52, recital 49 | §1 | 2026-10-18 |
| Tukes: "Responsibility for product safety" (tukes.fi/en/products-and-services/general-consumer-goods/responsibility-for-product-safety) — FI/SV instructions and safety information, Act 184/2025 | §1 | 2026-10-18 |
| Tukes news 6.5.2025 "Kuluttajatuotteiden turvallisuuden lainsäädäntö uudistui – uusi seuraamusmaksu viranomaisen käyttöön" | §1 penalty fee | 2026-10-18 |
| Tukes news 13.8.2024 "Uusi tuoteturvallisuusasetus tuo mallin yritysten palautusmenettelyilmoituksille" (recall notice template) | §1.6 | 2026-10-18 (implementing act number not confirmed: *verify*) |
| Regulation (EU) No 1007/2011, OJ L 272, 18.10.2011 — English and Finnish texts, Art. 2, 5, 7–9, 11, 12, 14–17, Annex I, III — http://data.europa.eu/eli/reg/2011/1007/oj | §2, Spec §2.2 | 2026-10-18 (later fibre-name additions by delegated acts not re-read) |
| Tukes: "Textiles" (tukes.fi/en/products-and-services/general-consumer-goods/textiles) | §2 languages | 2026-10-18 |
| Regulation (EC) No 1223/2009, OJ L 342, 22.12.2009 — Art. 4, 6, 13, 19, 20 — http://data.europa.eu/eli/reg/2009/1223/oj | §3 | 2026-10-18 (original text; annexes amended many times) |
| Tukes: "Labelling of cosmetics" (tukes.fi/en/chemicals/cosmetics/labelling-of-cosmetics) | §3 FI/SV items | 2026-10-18 |
| Commission Regulation (EU) No 655/2013 (claims common criteria) | §3.4 | 2026-10-18 |
| "Technical document on cosmetic claims", version of 3 July 2017, Annexes III–IV applicable from 1 July 2019 (Commission DocsRoom 24847) | §3.4, Spec §2.7.1 | 2026-10-18 |
| Commission Regulation (EU) 2023/1545 (fragrance allergens), transitional footnotes | §3.5 | 2026-10-18 |
| Directive 98/6/EC (price indication), Art. 2–5 | §4 | 2026-10-18 |
| Valtioneuvoston asetus 553/2013 kulutushyödykkeen hinnan ilmoittamisesta markkinoinnissa (Finlex PDF of the original, §3, §4, §8, §10) | §4 | 2026-10-18 (later amendment adding §7 a not re-read) |
| KKV: "Tavaroiden ja palveluiden hinnan ilmoittaminen" (Consumer Ombudsman guideline, drafted 2014) | §4 | 2026-10-18 |
| Directive (EU) 2024/825, OJ L, 6.3.2024 — recitals, Art. 1 definitions, Art. 4 (dates), Annex | §5 | 2026-10-18 |
| Kuluttajansuojalaki 38/1978, consolidated on Finlex incl. amendment 26.6.2026/573 (section headings ch. 2 and 6; ch. 6 §16 text) | §5, §6, §7 | 2026-10-18 |
| KKV: "Vastuullisuus- ja ympäristöväittämät markkinoinnissa (kommentoitavana)", comments until 21.10.2026 | §5 | 2026-10-18 (draft) |
| Suomen Yrittäjät: "Kuluttajansuojalaki muuttuu – vaikutuksia ympäristö- ja kestävyysväittämiin…" (secondary) | §5 transition | 2026-10-18 |
| Directive 2011/83/EU (CRD), Art. 6(1)(k), 16(e) | §6 | 2026-10-18 |
| Commission Notice 2021/C 525/01, guidance on the CRD, §5.11.4 | §6 | 2026-10-18 |
| CJEU C-681/17 *slewo*, judgment of 27.3.2019 (curia press release 42/19, via search extract) | §6 | 2026-10-18 (press release summary only) |
| Regulation (EU) 2022/2065 (DSA), Art. 29–32 | §7 | 2026-10-18 |
| Tukes: "Cords and drawstrings on children's clothing" (search extract of the Tukes page) | §8 | 2026-10-18 (extract) |
| Tukes: "Product safety and chemicals in jewellery and watches" / "Nikkelirajoitus ja kadmiumin ja lyijyn rajoitukset koruissa" (search extract) | §8 | 2026-10-18 (extract; REACH Annex XVII itself not re-read) |
| ECHA: "Chemicals in our life – right to ask", Guidance on requirements for substances in articles v4.0 (search extract) | §8 Art. 33 | 2026-10-18 (extract) |
| European Commission, Your Europe: "Footwear labelling" (last checked by the Commission 13/07/2026) | §9 | 2026-10-18 |
| Not read this session (general knowledge; *verify* before relying): EN 13402, EN 14682, ISO 3758 (paid standards); Directive 94/11/EC text; Regulation (EU) 2016/425 (PPE); Finnish precious-metals rules; rules of GOTS, Fairtrade, Leaping Bunny, The Vegan Society and other schemes; Ruokavirasto and Fimea borderline guidance | §8–§11, Spec §2.6, §2.10, §2.12 | — |
