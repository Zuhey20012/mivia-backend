# 02 — Draft articles of association (yhtiöjärjestys) built for founder control

> **Not legal advice.** A draft for a Finnish lawyer to review, written 3 November 2026. Statute references are to the Limited Liability Companies Act 624/2006 (osakeyhtiölaki, "OYL"), consolidated version `fin@20240652`, read from Finlex open data on 3 November 2026. The company name, domicile and every bracketed item are placeholders: the name "Malvoya Oy" has **not** been checked for availability.

## 0. Do you need these articles on day one?

While you own 100 % of the shares you already have complete control: you can change the articles alone at any time (a written unanimous shareholder decision, OYL ch. 5 §1, plus a change notification to PRH). The control features below start to matter the day a second person gets shares.

| Option | Cost now | Pros | Cons |
|---|---|---|---|
| **A. Guided package with standard articles now, these articles later** | 300 € (prh.fi, 3 Nov 2026) + a change notification later (fee not verified) | Cheapest, fastest | Must remember to change before the first co-founder, employee share or investor |
| **B. These articles from day one** | 400 € (prh.fi, 3 Nov 2026) | Everything is in place; transfers are protected from the start; data room is clean | Lawyer time now |

**Recommendation for the lawyer to confirm:** B, if the lawyer review is done anyway; otherwise A, with the change made before any share leaves your hands.

## 1. How control actually works under Finnish law (read this first)

These are the rules the articles must live with. They explain why some clauses are here and others belong in a shareholders' agreement (04).

1. **Ordinary decisions** (electing the board, approving accounts, dividends) pass with a **majority of votes cast** (OYL ch. 1 §6). Multiple-vote A shares therefore give you the board as long as your A votes exceed everyone else's votes.
2. **Qualified-majority decisions** need **two thirds of the votes cast AND two thirds of the shares represented** at the meeting (ch. 5 §27). These include changing the articles, a directed share issue (suunnattu osakeanti), option rights, mergers, demergers and liquidation. **The articles cannot lower this requirement** ("Määräenemmistövaatimusta ei voida lieventää yhtiöjärjestyksen määräyksellä"). Consequence: multiple votes give you a **veto** over these matters as long as you hold more than one third of the votes, but they do **not** let you pass them alone once you hold less than two thirds of the shares present. The articles **may** make these decisions harder (ch. 1 §9), which is how clause 13 below protects you.
3. **Class rights:** a change that merges classes or reduces a whole class's rights also needs the qualified majority within each class present **and** the consent of a majority of all shares of each class whose rights are reduced (ch. 5 §28). Your A-class rights cannot be taken away without the A holders.
4. **Equal treatment** (ch. 1 §7): all shares carry equal rights unless the articles say otherwise, and no organ may give anyone an unjustified benefit at the company's or another shareholder's expense. Control must be used in the company's interest.
5. **Minority rights the articles cannot remove** (examples): holders of 10 % of all shares can demand an extraordinary general meeting (ch. 5 §4) and a minimum dividend (vähemmistöosinko: half of the year's profit, capped at 8 % of equity, ch. 13 §7); an owner of more than 90 % of **all shares and votes** can redeem the rest, and the minority can demand it (ch. 18 §1).
6. **No cap on the vote ratio:** OYL ch. 3 §1 allows classes that differ in votes or in rights to distributions; no maximum difference was found in the Act (lawyer to confirm). The old 1:20 limit belonged to the repealed 1978 Act.

## 2. The draft (Finnish binding text, English translation)

> Placeholders: `[YHTIÖN NIMI]` = company name, `[KOTIPAIKKA]` = domicile municipality.

### 1 § Toiminimi ja kotipaikka / Name and domicile
**FI:** Yhtiön toiminimi on [YHTIÖN NIMI] Oy, ruotsiksi [YHTIÖN NIMI] Ab ja englanniksi [YHTIÖN NIMI] Ltd. Yhtiön kotipaikka on [KOTIPAIKKA].
**EN:** The company's name is [COMPANY NAME] Oy, in Swedish [COMPANY NAME] Ab and in English [COMPANY NAME] Ltd. The company's domicile is [MUNICIPALITY].

*Plain words:* the law requires the name, a Finnish municipality and the line of business (ch. 2 §3). Parallel names are optional, but every language version must be listed here if used. Choose the domicile where you want general meetings to be held by default.

### 2 § Toimiala / Line of business
**FI:** Yhtiön toimialana on verkkokauppapaikkojen ja muiden digitaalisten alustojen ylläpito, kehittäminen ja välittäjänä toimiminen; kuljetus-, kuriiri- ja toimituspalvelujen tuottaminen ja välittäminen; ohjelmistojen, mobiilisovellusten ja tietojärjestelmien kehittäminen, myynti, vuokraus ja lisensointi; mainonta-, markkinointi-, media- ja sisällöntuotantopalvelut, mukaan lukien suoratoisto; vaatteiden, jalkineiden, asusteiden, laukkujen, korujen, kosmetiikan, hiusten- ja ihonhoitotuotteiden, tuoksujen ja muiden kulutustavaroiden vähittäis- ja tukkukauppa, verkkokauppa, maahantuonti ja vuokraus; maksujen välittämiseen liittyvät palvelut siltä osin kuin ne eivät vaadi toimilupaa; konsultointi- ja tietopalvelut sekä muu edellä mainittuun liittyvä liiketoiminta. Yhtiö voi omistaa ja hallita osakkeita, muita arvopapereita, immateriaalioikeuksia ja kiinteistöjä sekä käydä niillä kauppaa.
**EN:** The company's line of business is operating, developing and acting as an intermediary on online marketplaces and other digital platforms; providing and brokering transport, courier and delivery services; developing, selling, renting and licensing software, mobile applications and information systems; advertising, marketing, media and content-production services, including live streaming; retail and wholesale trade, online trade, import and rental of clothing, footwear, accessories, bags, jewellery, cosmetics, hair and skin care products, fragrances and other consumer goods; services related to the transfer of payments to the extent they need no licence; consulting and information services; and other business related to the above. The company may own and manage shares, other securities, intellectual property and real estate and trade in them.

*Plain words:* broad on purpose, so that a new service (own-brand goods, ads, rentals, an international expansion) never needs an articles change. Payment services that need a licence are excluded on purpose: Stripe holds the licence. The TOL code in the start-up notification must fall within this text.

### 3 § Osakelajit / Share classes
**FI:** Yhtiön osakkeet jakautuvat A-sarjan ja B-sarjan osakkeisiin. Kukin A-sarjan osake tuottaa yhtiökokouksessa kymmenen (10) ääntä ja kukin B-sarjan osake yhden (1) äänen. Osakelajit tuottavat muutoin yhtiössä yhtäläiset oikeudet, myös yhtiön varoja jaettaessa. Osakkeilla ei ole nimellisarvoa.
**EN:** The company's shares are divided into A shares and B shares. Each A share carries ten (10) votes at a general meeting and each B share one (1) vote. Otherwise the classes carry equal rights, including in distributions of the company's assets. The shares have no nominal value.

*Plain words:* you hold A shares; investors and employees get B shares. Same money per share, different votes. With 10 votes per A share you keep the majority of votes (and so the board) as long as you hold **more than about 9.1 %** of all shares (10 × your shares > everyone else's shares). Example: you 100 000 A (1 000 000 votes); after three rounds investors hold 600 000 B (600 000 votes) = you own 14.3 % of the shares but 62.5 % of the votes.

### 4 § A-osakkeiden muuntaminen / Conversion of A shares (muuntolauseke)
**FI:** A-sarjan osake muuntuu B-sarjan osakkeeksi, kun se siirtyy muulle kuin (i) A-sarjan osakkeen omistajalle tai (ii) yhteisölle, jossa A-sarjan osakkeen omistajalla on kirjanpitolain 1 luvun 5 §:ssä tarkoitettu määräysvalta [, tai (iii) A-sarjan osakkeen omistajan perilliselle tai puolisolle perintönä, testamentilla tai ositusperusteella]. A-sarjan osakkeen omistaja voi lisäksi milloin tahansa vaatia kirjallisesti yhtiöltä A-sarjan osakkeidensa muuntamista B-sarjan osakkeiksi. Hallituksen on viipymättä ilmoitettava muuntaminen rekisteröitäväksi. Muuntaminen tulee voimaan, kun se on rekisteröity.
**EN:** An A share converts into a B share when it passes to anyone other than (i) a holder of A shares or (ii) an entity in which a holder of A shares has control within the meaning of chapter 1, section 5 of the Accounting Act [, or (iii) an heir or spouse of an A shareholder by inheritance, will or division of matrimonial property]. A holder of A shares may also at any time demand in writing that the company convert their A shares into B shares. The board must notify the conversion for registration without delay. The conversion takes effect when registered.

*Plain words:* the 10 votes belong to you (or your holding company), not to whoever later buys the shares. A buyer gets ordinary B shares. Investors expect this; it also makes the structure easier to accept. Item (iii) is your choice: keep it to pass control to family, delete it if you prefer control to end with you. The conversion clause (muuntolauseke) is expressly allowed by OYL ch. 3 §1, and takes effect only on registration.

### 5 § Hallitus / Board
**FI:** Yhtiöllä on hallitus, johon kuuluu yhdestä viiteen (1–5) varsinaista jäsentä. Jos hallitukseen kuuluu vähemmän kuin kolme varsinaista jäsentä, hallitukseen valitaan yhdestä kolmeen (1–3) varajäsentä. Hallituksen jäsenten toimikausi on toistaiseksi voimassa. Yhtiökokous valitsee hallituksen puheenjohtajan.
**EN:** The company has a board of one to five (1–5) ordinary members. If the board has fewer than three ordinary members, one to three (1–3) deputy members are elected. Board members serve until further notice. The general meeting elects the chair of the board.

*Plain words:* the law already sets 1–5 members and a deputy below three (ch. 6 §8); the articles repeat it for clarity. **The general meeting**, where your A votes decide, elects and can remove every member (ch. 6 §§9, 13) and also the chair, so the board cannot pick a different chair. An investor board seat is promised in the shareholders' agreement (04), not here; the law would also allow the articles to let a minority group appoint fewer than half of the members directly (ch. 6 §9), which you should not offer early.

### 6 § Toimitusjohtaja / Managing director
**FI:** Yhtiöllä voi olla toimitusjohtaja, jonka hallitus valitsee.
**EN:** The company may have a managing director, elected by the board.

### 7 § Yhtiön edustaminen / Representing the company
**FI:** Yhtiötä edustaa hallitus. Lisäksi yhtiötä edustavat hallituksen puheenjohtaja yksin sekä kaksi hallituksen jäsentä yhdessä. Toimitusjohtaja edustaa yhtiötä tehtäviinsä kuuluvissa asioissa. Hallitus voi antaa nimetylle henkilölle oikeuden edustaa yhtiötä.
**EN:** The board represents the company. In addition, the chair of the board alone and two board members jointly represent the company. The managing director represents the company in matters within their duties. The board may authorise a named person to represent the company.

*Plain words:* you, as chair, can sign contracts alone without a board meeting each time (ch. 6 §26 allows such clauses). After investors join, "two members jointly" lets the board function even if you are away, but the chair-alone right stays with whoever the general meeting (you) makes chair.

### 8 § Tilikausi / Financial period
**FI:** Yhtiön tilikausi on kalenterivuosi.
**EN:** The company's financial period is the calendar year.

### 9 § Kokouskutsu / Notice of general meetings
**FI:** Kutsu yhtiökokoukseen toimitetaan osakkeenomistajille sähköpostilla osakasluetteloon merkittyyn tai osakkeenomistajan yhtiölle ilmoittamaan sähköpostiosoitteeseen taikka kirjeellä osakasluetteloon merkittyyn osoitteeseen aikaisintaan kaksi (2) kuukautta ja viimeistään yksi (1) viikko ennen kokousta. Osakkeenomistaja, jonka sähköpostiosoite ei ole yhtiön tiedossa, saa kutsun kirjeellä.
**EN:** Notice of a general meeting is sent to shareholders by email to the address entered in the shareholder register or notified to the company by the shareholder, or by letter to the address in the shareholder register, no earlier than two (2) months and no later than one (1) week before the meeting. A shareholder whose email address the company does not know receives the notice by letter.

*Plain words:* the default is a written notice to every shareholder whose address is known (ch. 5 §20), at the earliest two months and at the latest one week before the meeting (ch. 5 §19). Email keeps it cheap and fast. A meeting about changing the articles in the ways listed in ch. 5 §29 always needs a written notice to each shareholder (ch. 5 §20); the lawyer should confirm that email counts as "written". A short notice period lets you act quickly; investors may ask for two weeks in the shareholders' agreement.

### 10 § Yhtiökokous / General meeting
**FI:** Yhtiökokous voidaan pitää yhtiön kotipaikassa tai Helsingissä. Hallitus voi päättää, että yhtiökokoukseen voi osallistua tietoliikenneyhteyden ja teknisen apuvälineen avulla, tai että yhtiökokous järjestetään ilman kokouspaikkaa siten, että osakkeenomistajat käyttävät päätösvaltaansa täysimääräisesti ja ajantasaisesti tietoliikenneyhteyden ja teknisen apuvälineen avulla kokouksen aikana (etäkokous).
Varsinainen yhtiökokous pidetään vuosittain kuuden (6) kuukauden kuluessa tilikauden päättymisestä. Kokouksessa päätetään laissa varsinaiselle yhtiökokoukselle säädetyistä asioista.
**EN:** A general meeting may be held at the company's domicile or in Helsinki. The board may decide that shareholders may take part by a telecommunication connection and technical means, or that the general meeting is held without a meeting venue so that shareholders exercise their decision-making power in full and in real time by a telecommunication connection and technical means during the meeting (remote meeting).
The annual general meeting is held each year within six (6) months of the end of the financial period. It decides the matters the law assigns to the annual general meeting.

*Plain words:* a fully remote meeting is possible only if the articles allow it (ch. 5 §16). The six-month rule is the law's own (ch. 5 §3). While you are the only shareholder, every meeting can instead be a signed, dated, numbered written decision (ch. 5 §1).

### 11 § Lunastuslauseke / Redemption clause
**FI:** Jos osake siirtyy muulle kuin yhtiölle, osakkeen siirron perusteesta riippumatta, on ensisijaisesti A-sarjan osakkeiden omistajilla, toissijaisesti muilla osakkeenomistajilla ja viimesijaisesti yhtiöllä oikeus lunastaa osake. Jos useampi samalla etusijalla oleva haluaa käyttää lunastusoikeuttaan, osakkeet jaetaan heidän kesken heidän omistamiensa osakkeiden suhteessa ja jäljelle jäävät osakkeet arvalla. Lunastusoikeutta ei ole, kun osake siirtyy (i) A-sarjan osakkeen omistajalle tai (ii) yhteisölle, jossa A-sarjan osakkeen omistajalla on kirjanpitolain 1 luvun 5 §:ssä tarkoitettu määräysvalta. Lunastushinta on osakkeen käypä hinta, jona vastikkeellisessa saannossa muun selvityksen puuttuessa pidetään sovittua hintaa. Lunastuksessa noudatetaan muutoin osakeyhtiölain 3 luvun 7 §:ää.
**EN:** If a share passes to anyone other than the company, whatever the basis of the transfer, first the holders of A shares, secondly the other shareholders and lastly the company have the right to redeem the share. If several persons with the same priority wish to redeem, the shares are divided among them in proportion to their holdings and any remaining shares by lot. There is no redemption right when a share passes (i) to a holder of A shares or (ii) to an entity in which a holder of A shares has control within the meaning of chapter 1, section 5 of the Accounting Act. The redemption price is the share's fair value, which in a transfer for consideration is taken to be the agreed price unless shown otherwise. Otherwise chapter 3, section 7 of the Companies Act applies.

*Plain words:* if anyone sells or otherwise transfers shares (also by gift, inheritance or divorce), you get the first chance to buy them at a fair price, so no stranger enters the company against your will. The law fixes the deadlines and they cannot be extended (ch. 3 §7: the board notifies within one month; the claim within two months; payment within one month after that). The company can redeem only with distributable funds (ch. 3 §7). Your own transfers to your holding company are exempt.

### 12 § Suostumuslauseke / Consent clause
**FI:** Osakkeen hankkimiseen luovutustoimin tarvitaan yhtiön suostumus. Suostumuksen antamisesta päättää hallitus. Suostumusta ei tarvita, kun osake siirtyy A-sarjan osakkeen omistajalle tai yhteisölle, jossa A-sarjan osakkeen omistajalla on kirjanpitolain 1 luvun 5 §:ssä tarkoitettu määräysvalta. Hallitus voi jättää suostumuksen antamatta, jos osakkeen hankkija on yhtiön kilpailija tai kilpailijan lähipiiriä tai jos hankinta on muuten yhtiön edun vastainen.
**EN:** Acquiring a share by transfer requires the company's consent. The board decides on consent. Consent is not needed when a share passes to a holder of A shares or to an entity in which a holder of A shares has control within the meaning of chapter 1, section 5 of the Accounting Act. The board may refuse consent if the acquirer is a competitor of the company or related to a competitor, or if the acquisition is otherwise against the company's interest.

*Plain words:* a buyer needs the board's yes before becoming a shareholder; you control the board. If the board does not answer in writing within **two months**, consent is deemed given (ch. 3 §8), so the board must answer every request on time. The clause does not apply to shares bought at a forced auction or from a bankruptcy estate (ch. 3 §8). Together with clause 11 this means: a share can only change hands with the board's consent, and even then you can buy it first. Only these two kinds of transfer restriction are allowed in the articles (ch. 3 §6); anything stronger (lock-ups, drag-along) goes in the shareholders' agreement.

### 13 § Erityinen enemmistövaatimus / Additional majority requirement
**FI:** Yhtiökokouksen päätös, joka koskee yhtiöjärjestyksen muuttamista, suunnattua osakeantia, optio-oikeuksien tai muiden osakkeisiin oikeuttavien erityisten oikeuksien antamista, sulautumista, jakautumista, kotipaikan siirtoa, yhtiön asettamista selvitystilaan tai yhtiön koko liiketoiminnan tai olennaisen osan siitä luovuttamista, on pätevä vain, jos sitä osakeyhtiölaissa säädetyn enemmistön lisäksi kannattavat A-sarjan osakkeiden omistajat, joilla on yli puolet kaikista A-sarjan osakkeista.
**EN:** A general meeting decision on amending the articles, a directed share issue, granting option rights or other special rights entitling to shares, a merger, a demerger, transfer of the domicile abroad, placing the company in liquidation or transferring all or a substantial part of the company's business is valid only if, in addition to the majority required by the Companies Act, it is supported by holders of more than half of all A shares.

*Plain words:* this is the strongest lawful control lever. The law lets articles make qualified-majority decisions **harder**, never easier (ch. 1 §9, ch. 5 §27). So even if you one day hold less than one third of the shares, nobody can change the articles, dilute you with a directed issue, merge or sell the business without you. Investors will ask for the mirror image (a B-class or investor-majority veto) in the shareholders' agreement; that is normal and is negotiated there.

### 14 § Merkintäetuoikeus / Pre-emption in share issues
**FI:** Osakeannissa osakkeenomistajilla on etuoikeus annettaviin osakkeisiin osakeyhtiölain 9 luvun 3 §:n mukaisesti.
**EN:** In a share issue, shareholders have a pre-emptive right to the new shares in accordance with chapter 9, section 3 of the Companies Act.

*Plain words:* by law every shareholder may subscribe for new shares in proportion to what they hold, class by class (ch. 9 §3). A private company's articles may change this (ch. 9 §3). Keeping the default protects you from dilution as much as anyone; the founder-specific protection is clause 13 (a directed issue needs the A holders). Some lawyers draft "A holders get A shares, B holders get B shares" here; the statutory text already does that.

### 15 § Riitojen ratkaiseminen / Disputes (optional)
**FI:** Yhtiön ja hallituksen, hallituksen jäsenen, toimitusjohtajan tai osakkeenomistajan väliset sekä osakkeenomistajien väliset yhtiöoikeudelliset riidat ratkaistaan Keskuskauppakamarin välimiesmenettelysääntöjen mukaisesti yhden välimiehen välimiesmenettelyssä Helsingissä suomen kielellä.
**EN:** Company-law disputes between the company and the board, a board member, the managing director or a shareholder, and between shareholders, are finally settled in arbitration under the Arbitration Rules of the Finland Chamber of Commerce by one arbitrator in Helsinki in Finnish.

*Plain words:* private, faster and confidential, but expensive for small disputes. Lawyer to decide whether to include it now or only in the shareholders' agreement.

## 3. Trade-offs of A/B shares and how investors react

| | For the founder | For investors |
|---|---|---|
| Control | Board and ordinary decisions stay with you down to ≈ 9 % ownership | They cannot replace the board or management by votes |
| Qualified decisions | Veto (more than one third of votes) and clause 13 | They usually get a veto in the shareholders' agreement |
| Valuation | Some investors pay less or pass | Lower liquidity and governance risk for them |
| Exit / IPO | Dual-class is common in tech listings abroad; Nasdaq Helsinki also has A/B companies | Buyers usually require conversion to one class at exit |

**How investors usually react (planning guidance, not data):**
- **Angels and pre-seed:** often accept A/B if the founder is clearly the company and investors get information rights and a few vetoes.
- **Nordic seed and Series A funds:** commonly ask for (a) automatic conversion on transfer (clause 4 already does this), (b) a **sunset** (A shares convert after N years, at IPO, or if the founder leaves or holds under a threshold), (c) a preferred class with liquidation preference instead of plain B shares, and (d) vetoes on reserved matters. Some decline dual-class entirely. The fundraising plan (`docs/business/fundraising-plan.md`) expects 15–25 % dilution per round; with A shares at 10 votes you keep vote control through roughly four such rounds.
- **Your negotiating line:** keep the A/B votes and clause 13, accept conversion on transfer and a long or performance-based sunset (for example only if you leave the company as a "bad leaver" or after an IPO), and give investors vetoes in the shareholders' agreement rather than in the articles. See 04.

## 4. Other lawful control tools (not in the draft, for the lawyer)

- **Founder holding company** owning the A shares: control stays with you even if you later move abroad or restructure (01 §3).
- **Chair right to sign alone** (clause 7) and **chair elected by the general meeting** (clause 5).
- **Option and share plans in B shares only**, with the board (you) deciding grants within an authorisation from the general meeting (OYL ch. 9 and ch. 10 on option rights; section numbers not checked here; investors will require a cap).
- **Shareholders' agreement** for everything the articles cannot do: drag-along, tag-along, lock-ups, leaver terms, information rights (04).
- What **not** to do: anything that gives you an unjustified benefit at the company's or another shareholder's expense breaches ch. 1 §7 and can be challenged; control must be used in the company's interest.

## 5. Sources (read 3 November 2026)

- Finlex open data, OYL 624/2006 consolidated `fin@20240652`: https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute-consolidated/2006/624/fin@20240652 — ch. 1 §§3, 6, 7, 9; ch. 2 §3; ch. 3 §§1, 6, 7, 8; ch. 5 §§1, 3, 4, 16, 19, 20, 27, 28; ch. 6 §§8, 9, 13, 26; ch. 9 §3; ch. 13 §7; ch. 18 §1.
- PRH, Alternatives A (300 €) and B (400 €): https://prh.fi/en/companiesandorganisations/yrityksen_perustaminen/osakeyhtio.html
- Not verified here: the change-notification fee for amending the articles; the Finland Chamber of Commerce arbitration rules (clause 15).
