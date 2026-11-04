# 03 — Intellectual property, brand and accounts owned by the company

> **Not legal advice.** Preparation for a Finnish lawyer, written 3 November 2026. Copyright Act 404/1961 (tekijänoikeuslaki) was read from Finlex open data, consolidated version `fin@20230263`, on 3 November 2026; Trademarks Act 544/2019 (tavaramerkkilaki) from its original text the same day; PRH trademark fees from prh.fi the same day. `[PLACEHOLDERS]` are to be filled by the founder. Domain and name availability have **not** been checked.

## 1. What has to move into the company

Everything below was created before the company existed, so today it belongs to the founder personally (or to whoever else contributed). Investors check this first (`docs/business/fundraising-plan.md`, "IP owned by the company").

| Asset | Where | Notes |
|---|---|---|
| Source code | `backend/`, `Malvoya_customer/`, `malvoya_vendor/`, `malvoya_courier/`, `malvoya_admin/`, `web/`, `packages/`, `functions/` (dead code), CI in `.github/` | The GitHub repository `Zuhey20012/mivia-backend` is **public** (`CLAUDE.md`). |
| Designs | Brand mark "Thread M" (`lib/widgets/brand_mark.dart`, `assets/brand/`), "Birch Market" style, colours, `docs/design/`, `docs/design-system/`, store assets and screenshots | |
| Texts | `legal/*.md`, `legal/Malvoya_NDA.docx`, `docs/**`, store listings, help content in `web/src/content`, in-app copy | |
| Brand | The name "Malvoya", logo, app names "Malvoya", "Malvoya Store", "Malvoya Courier", application IDs `com.malvoya.*` | Old name "Mivia" leftovers (`mivia_*`) can be ignored. |
| Data | Production database (test accounts only), Cloudinary media, Firebase project | Data is not "IP" but the accounts holding it must be the company's (§4). |
| Accounts and keys | GitHub, Render, Firebase/Google Cloud, Stripe, Cloudinary, Apple, Google Play, LiveKit, Sentry, Twilio, OpenRouteService, email, domains, Android upload keystore, Apple certificates | §4–§6. |

**Third-party material that stays third-party (licence inventory to keep):** bundled fonts Hanken Grotesk and Bricolage Grotesque (registered in `core/font_licenses.dart`), npm and pub packages, Material Symbols icons, OpenStreetMap tiles (attribution required), the licensed sound library (`Sound` rows carry the licence text and URL). The company does not own these; it must follow their licences. **Action:** generate an open-source licence list for each app and the backend (a licence-scanning tool) and keep it in the data room.

**Other contributors:** if anyone other than the founder ever wrote code, designs or texts (a friend, a freelancer, a designer of the logo), the company needs a written assignment from them too. **Action:** list every contributor from the repository history and every design/text source, and collect assignments.

## 2. The founder's assignment of IP to the company

### 2.1 Why a written assignment, and what the law says (read 3 Nov 2026)

- Copyright belongs to the person who created the work, and computer programs are protected as literary works (Copyright Act §1).
- Copyright can be transferred in whole or in part (§27).
- **Unless agreed otherwise, the buyer of a copyright may not modify the work or transfer the right onward** (§28). The assignment must therefore expressly give the company the right to modify, develop, sublicense and transfer onward, or the company could not freely change the code or sell the business.
- **Moral rights** (the right to be named and to the work's integrity) can be waived only for use "limited in kind and scope" (§3). They do not stop normal software development; the assignment should record a waiver as far as the law allows.
- The automatic transfer of software copyright to an employer (§40 b) covers only programs made **in an employment relationship**. It does not cover work done before the company existed, nor designs and texts, nor contractors.
- An author who assigns exclusive rights has a right to **appropriate and proportionate remuneration** (§28 a), which cannot be excluded by contract; this mandatory rule does not apply to authors of computer programs (§27). For designs and texts the lawyer should confirm what consideration is appropriate when the author is also the sole owner.

### 2.2 How to pay for it (decision for the accountant)

| Option | How | Notes |
|---|---|---|
| Nominal price | The company pays e.g. 1 € | Simple. Accountant: tax treatment of a below-market transfer to one's own company. |
| Fair price as a founder loan | The company owes the founder the value, paid later | Creates a balance-sheet asset and a debt; needs a valuation. |
| In-kind subscription (apportti) | IP given as payment for shares at founding | Needs an auditor's statement on the value (OYL ch. 2); usually not worth the cost at this stage. |

Recommendation for discussion: **nominal price, signed right after registration**, with a board decision accepting it.

### 2.3 Draft assignment agreement (FI binding / EN translation)

**IMMATERIAALIOIKEUKSIEN LUOVUTUSSOPIMUS / INTELLECTUAL PROPERTY ASSIGNMENT AGREEMENT**

**1. Osapuolet / Parties**
Luovuttaja / Assignor: [FOUNDER FULL LEGAL NAME], [HENKILÖTUNNUS], [ADDRESS] ("Luovuttaja" / "Assignor").
Luovutuksensaaja / Assignee: [COMPANY NAME] Oy, Y-tunnus [Y-TUNNUS], [ADDRESS] ("Yhtiö" / "Company").

**2. Tausta / Background**
FI: Luovuttaja on ennen Yhtiön perustamista luonut Malvoya-palvelun ohjelmistot, suunnitelmat, tekstit ja tunnukset. Osapuolet haluavat, että kaikki niihin liittyvät oikeudet kuuluvat Yhtiölle.
EN: Before the Company was founded, the Assignor created the software, designs, texts and brand of the Malvoya service. The parties want all rights in them to belong to the Company.

**3. Luovutettavat oikeudet / Assigned rights**
FI: Luovuttaja luovuttaa Yhtiölle täydellä omistusoikeudella ja ilman aika- tai aluerajoituksia kaikki taloudelliset oikeudet, mukaan lukien tekijänoikeudet, oikeudet tietokantoihin, liikesalaisuuksiin, toiminimiin ja tunnuksiin, rekisteröimättömiin tavaramerkkeihin ja verkkotunnuksiin, liitteessä 1 kuvattuun aineistoon ja sen kaikkiin aiempiin ja keskeneräisiin versioihin, lähdekoodiin, objektikoodiin, dokumentaatioon, suunnitelmiin, kuviin, teksteihin ja muihin aineistoihin ("Aineisto"), siltä osin kuin tällaisia oikeuksia on olemassa.
EN: The Assignor assigns to the Company, in full ownership and without limitation in time or territory, all economic rights, including copyright, database rights, rights in trade secrets, business names and symbols, unregistered trademarks and domain names, in the material described in Appendix 1 and all its earlier and unfinished versions, source code, object code, documentation, designs, images, texts and other material (the "Material"), to the extent such rights exist.

**4. Muuttaminen ja edelleenluovutus / Modification and onward transfer**
FI: Yhtiöllä on oikeus vapaasti muuttaa, kehittää, yhdistellä, kääntää, julkaista ja lisensioida Aineistoa sekä luovuttaa oikeudet edelleen kokonaan tai osittain (tekijänoikeuslain 28 §).
EN: The Company may freely modify, develop, combine, translate, publish and license the Material and transfer the rights onward in whole or in part (Copyright Act §28).

**5. Moraaliset oikeudet / Moral rights**
FI: Luovuttaja ei vaadi nimeään mainittavaksi Aineiston käytön yhteydessä ja hyväksyy Aineiston muuttamisen, siltä osin kuin laki sallii (tekijänoikeuslain 3 §).
EN: The Assignor does not require being named when the Material is used and accepts its modification, to the extent the law allows (Copyright Act §3).

**6. Tilit, avaimet ja rekisteröinnit / Accounts, keys and registrations**
FI: Luovuttaja siirtää tai auttaa siirtämään Yhtiön nimiin liitteessä 2 luetellut tilit, verkkotunnukset, sovelluskauppojen sovellukset, allekirjoitusavaimet ja salaisuudet sekä allekirjoittaa tarvittavat asiakirjat. Kunnes siirto on tehty, Luovuttaja hallitsee niitä Yhtiön lukuun.
EN: The Assignor transfers, or helps transfer, to the Company the accounts, domain names, app-store apps, signing keys and secrets listed in Appendix 2 and signs any documents needed. Until the transfer is done, the Assignor holds them on the Company's behalf.

**7. Kolmansien osapuolten aineisto / Third-party material**
FI: Aineisto sisältää avoimen lähdekoodin ohjelmistoja, fontteja ja muuta kolmansien osapuolten aineistoa niiden omilla lisensseillä (liite 3). Niiden osalta luovutus koskee vain Luovuttajan omia oikeuksia.
EN: The Material contains open-source software, fonts and other third-party material under their own licences (Appendix 3). For those, the assignment covers only the Assignor's own rights.

**8. Tekoälyavusteinen aineisto / AI-assisted material**
FI: Osa Aineistosta on tuotettu tekoälytyökalujen avulla Luovuttajan ohjauksessa. Luovutus kattaa kaikki Luovuttajalle tällaiseen aineistoon kuuluvat oikeudet. Luovuttaja ei vakuuta, että jokainen Aineiston osa on tekijänoikeudella suojattu.
EN: Part of the Material was produced with AI tools under the Assignor's direction. The assignment covers all rights the Assignor has in such material. The Assignor does not warrant that every part of the Material is protected by copyright.

**9. Vakuutukset / Assurances**
FI: Luovuttaja vakuuttaa, ettei ole luovuttanut tai lisensioinut Aineistoa kenellekään muulle eikä tiedä Aineiston loukkaavan kolmannen oikeuksia, lukuun ottamatta liitteessä 3 mainittuja lisenssiehtoja.
EN: The Assignor confirms not having assigned or licensed the Material to anyone else and not knowing of any infringement of third-party rights by the Material, other than the licence terms listed in Appendix 3.

**10. Vastike / Consideration**
FI: Yhtiö maksaa Luovuttajalle [1] euroa [tai: [AMOUNT] euroa, joka kirjataan Yhtiön velaksi Luovuttajalle].
EN: The Company pays the Assignor [1] euro [or: [AMOUNT] euros, recorded as the Company's debt to the Assignor].

**11. Tulevat lisäykset / Future additions**
FI: Aineistoon, jonka Luovuttaja luo Yhtiölle tämän sopimuksen jälkeen muuten kuin työsuhteessa, sovelletaan tätä sopimusta.
EN: This agreement applies to material the Assignor creates for the Company after this agreement other than in an employment relationship.

**12. Sovellettava laki / Governing law:** Suomen laki; riidat [Helsingin käräjäoikeudessa]. / Finnish law; disputes in [Helsinki District Court].

**Allekirjoitukset / Signatures:** [PLACE, DATE] — Assignor: [FOUNDER]; for the Company: [FOUNDER as chair of the board] (with a decision dated [DATE] approving it). A board member may not take part in handling a contract between themself and the company (OYL ch. 6 §4, read 3 Nov 2026), so the founder is disqualified on the company side: the **deputy board member** takes the board decision and signs for the company, or the lawyer chooses another route (for example a written decision of the sole shareholder). This is one of the deputy's real jobs.
Appendices: 1 — list of material (repository paths, design files, texts, brand); 2 — accounts and keys (§4 below); 3 — third-party licence list.

## 3. Trademark "Malvoya"

### 3.1 What to file

1. **Word mark** "MALVOYA" first (protects the name in any font or logo).
2. **Figurative mark** (the Thread M logo with or without the word) later, once the logo is final.
3. Search first: TMview, the PRH database and EUIPO eSearch, for identical and similar marks in the same classes (paperwork checklist step 1 has not been done in a register).

### 3.2 Classes (Nice classification; lawyer or trademark attorney to word the lists)

| Class | Covers for Malvoya | Priority |
|---|---|---|
| 35 | Online marketplace services; retail services for clothing, footwear, accessories, jewellery, cosmetics; advertising and promotional services for others (drops, live shopping) | Must |
| 9 | Downloadable mobile applications and software | Must |
| 39 | Delivery of goods; courier services; transport and storage | Must |
| 42 | Software as a service; platform as a service; hosting of online marketplaces | Must |
| 38 | Streaming of audio and video; providing online forums and chat (live shopping, order chat) | Consider |
| 3 | Cosmetics, skin and hair care, fragrances | Only for own-brand beauty products |
| 25 | Clothing, footwear, headwear | Only for own-brand clothing |

A mark can be cancelled for a class where it is not genuinely used within five years of registration (Trademarks Act; lawyer to confirm the section); do not file classes 3 and 25 "just in case" unless an own brand is planned.

### 3.3 Costs (online)

| Office | Fee | Example |
|---|---|---|
| PRH (Finland) | 250 € incl. one class + 100 € per extra class; renewal the same; opposition 310 € (prh.fi, read 3 Nov 2026) | 4 classes = 550 €; 6 classes = 750 € |
| EUIPO (whole EU) | 850 € first class, 50 € second, 150 € each further (paperwork checklist, read 16 Oct 2026; EUIPO's page refused access on 3 Nov 2026) | 4 classes = 1 200 €; 6 classes = 1 500 € |

Suggested path: PRH now (cheap, Finland-only launch), EUIPO within 6 months to keep the PRH filing date as priority (Paris Convention priority; trademark attorney to confirm), or EUIPO directly if Nordic/Baltic expansion is planned within 2–3 years. Check whether EU SME support for IP fees is open in the year of filing (not verified).

### 3.4 Duration

A Finnish registration is valid for **10 years from the filing date** and can be renewed for 10 years at a time; PRH reminds the owner at least six months before expiry, but a missing reminder does not extend it; renewal is possible at the earliest one year before expiry (Trademarks Act 544/2019 §30, read 3 Nov 2026). See 06 for the calendar entry.

### 3.5 Name conflict risks

- `malvoya.com` is held by someone else (`CLAUDE.md`). Find out who (WHOIS/RDAP) and whether they use the name for any goods or services. If they do, the lawyer should assess the risk before marketing.
- The trade-register name, the trademark and the domain should match. A company name registered at PRH is **not** a trademark and does not by itself protect the brand.

## 4. Domains, stores and accounts in the company's name

### 4.1 Rules for every account

1. **Owner = the company**, identified by its legal name and Y-tunnus where the service allows; login on a **company email address** (e.g. `[admin@COMPANY DOMAIN]`), never a personal Gmail.
2. **The founder is the top-level owner/administrator**; every other person gets the **least role** that does the job (developer, analyst, support), never owner. Remove people the day they leave (05 offboarding list).
3. **Billing** on the company's card or invoice, so the account is plainly the company's asset.
4. **2FA everywhere** (§5), with a documented recovery path that does not depend on one phone.
5. Record each account in the **account register** (template §4.3) kept in the company's password manager.

### 4.2 Account-by-account plan

| Service | What to set up | Owner / roles | Notes |
|---|---|---|---|
| Domains | Register `[DOMAIN].fi` at a Traficom-accredited registrar and `[DOMAIN].com` (availability not checked); registrant = the company with its Y-tunnus | Company; founder as contact | Auto-renew on, registrar lock, 2FA; domain contact email on the company domain. |
| Email | Business email on the company domain (Google Workspace, Microsoft 365 or similar); SPF, DKIM, DMARC; `SMTP_FROM`, `SUPPORT_EMAIL`, `SECURITY_CONTACT` | Founder super-admin + one break-glass admin account stored in the safe | Accept the provider's DPA (05 §4). |
| GitHub | Create a GitHub **organisation** in the company name; transfer `mivia-backend` into it; **make it private** or decide what stays public; branch protection on `master`; Actions secrets owned by the org | Founder = org owner; others = members with repo-level roles | Making it private disables free CodeQL (`.github/workflows/codeql.yml` skips itself); budget for that or another scanner. |
| Render | Workspace/team in the company name; move `malvoya-api-eu`, `malvoya-db-eu`, `malvoya-admin` into it; company billing | Founder = owner; others = developer | Suspend the old Oregon services (`CLAUDE.md`). |
| Firebase / Google Cloud | Google Cloud organisation on the company domain; project and billing account owned by it; FCM, Auth, Crashlytics, App Distribution | Founder = Owner via company account; service accounts least-privilege | Re-issue `FIREBASE_SERVICE_ACCOUNT` from the company project if the project moves. |
| Stripe | Activate live mode as the Oy; Connect platform profile | Founder = Owner/Administrator; others Developer/Analyst/Support | Stripe KYC needs the registered name, Y-tunnus, beneficial owners, bank account. |
| Cloudinary | Account on the company email; choose an EU region if offered (records-of-processing has `[CLOUDINARY ACCOUNT REGION]`) | Founder = admin | API secret stays only in Render. |
| Apple Developer | Organisation enrolment (D-U-N-S, company website) | Founder = Account Holder; others Admin/Developer | 99 USD/year. Sign in with Apple keys and `APPLE_TEAM_ID` move with it. |
| Google Play Console | Organisation account (D-U-N-S); transfer the three apps from any personal account | Founder = account owner; others limited | Play App Signing on; keep the **upload keystore** in the safe (losing it blocks updates until reset). |
| D-U-N-S | Request with the exact trade-register name and address | Company | Free. |
| LiveKit, Sentry, Twilio, OpenRouteService, Redis provider | Accounts on the company email; EU regions where offered (Sentry EU) | Founder = owner | Accept DPAs (05 §4). |
| Bank, OmaVero, PRH/YTJ, Incomes Register, Ilmoitin.fi | Company access through Suomi.fi e-Authorizations (Suomi.fi-valtuudet) | Founder; the accountant gets a limited authorisation | Never share personal bank credentials with the accountant. |
| AI and design tools used to build Malvoya | Company plan where possible; check output-ownership terms | Founder | §7. |

### 4.3 Account register template (keep in the password manager, not in git)

| Service | Legal owner | Login email | Owner role | Other users and roles | 2FA method | Recovery codes location | Billing | DPA accepted (date) | Last review |
|---|---|---|---|---|---|---|---|---|---|

## 5. Two-factor authentication everywhere

- **Preferred:** two hardware security keys (FIDO2/passkeys) per owner account: one carried, one in the safe. Then an authenticator app. **Avoid SMS** where another method exists (SIM-swap risk).
- **Recovery codes** printed and kept in a sealed envelope in a locked safe, and in the company password manager.
- The admin panel already enforces authenticator codes for ADMIN accounts in production (`ADMIN_MFA_REQUIRED`, `CLAUDE.md`); keep it on.

## 6. Credentials and recovery plan ("if the founder is hit by a bus")

1. **Company password manager** (business plan) with the account register, owned by the company account; the founder is the owner.
2. **Emergency kit** (sealed envelope, at the lawyer's or in a bank safe-deposit box): how to reach the password manager's emergency access, the break-glass email admin, where the hardware keys are, and a one-page "what to do" for the deputy board member (01 §4.3). The deputy gets access **only** through this kit, never day to day.
3. **Critical secrets with a written backup** (encrypted, offline): `JWT_SECRET`, `JWT_REFRESH_SECRET`, `DATA_ENCRYPTION_KEY` (**losing it makes every stored seller TIN unreadable**, DAC7), Android upload keystore and passwords (`android/key.properties`), Apple signing certificates, Stripe keys, `FIREBASE_SERVICE_ACCOUNT`, Cloudinary secret.
4. **Rotation:** rotate secrets when anyone with access leaves, after any suspected leak, and at least yearly (06).
5. **Test the recovery once a year** (06): sign in to each owner account with the backup key from the safe.

## 7. AI-generated code and content

- Much of Malvoya's code and documentation was written with AI assistance. Finnish copyright protects a work created by a person (Copyright Act §1), and EU case law requires originality in the sense of the author's own intellectual creation (CJEU C-5/08 *Infopaq*; not re-read here). **Output generated by an AI without sufficient human creative choices may have no copyright at all.** Parts where the founder made the creative choices (architecture, selection, arrangement, editing) are more likely protected.
- **What that means in practice:**
  1. The company cannot rely on copyright alone to stop copying. Protect the business with **trade secrets** (the Trade Secrets Act 595/2018 requires reasonable secrecy measures, which a **public** repository defeats), contracts (NDA, contractor terms), the **trademark**, the data and the network of shops and couriers.
  2. The assignment (§2.3, clause 8) transfers whatever rights exist and does not promise more.
  3. In investor due diligence, **disclose** AI use; do not warrant that "all code is original copyright work".
  4. Check each AI tool's terms for who owns the output and whether the provider offers any indemnity; keep the plan type and dates in the account register.
  5. Run a **licence and snippet scan** to catch code that reproduces open-source code under a licence that would bind the company.
  6. Keep the record of human decisions: architecture decision records (`docs/adr/`), design docs, commit history.
- **Recommendation:** have the lawyer review this section and the assignment's clause 8 before the first investor conversation.

## 8. Edits needed elsewhere (not made here)

- `legal/Malvoya_NDA.docx`: names "Malvoya Oy" and a "Registered Address: Helsinki" that do not exist yet; describes Firebase/Google Cloud as the infrastructure, a "5 %–10 % commission" and a "€3.00 guaranteed base rate", none of which matches the product today (0 % commission since 2.13.0; courier pay formula in `utils/courierPay.ts`). Rewrite before use (05 §3).
- `.github/workflows/codeql.yml`: decide the scanner once the repository is private.
- `SECURITY.md` / `SECURITY_CONTACT`: point to a company-domain mailbox once it exists.

## 9. Sources (read 3 November 2026 unless noted)

- Finlex open data, Copyright Act 404/1961, consolidated `fin@20230263`: https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute-consolidated/1961/404/fin@20230263 — §§1, 3, 27, 28, 28 a, 40 b.
- Finlex open data, Trademarks Act 544/2019 (original text; later amendments not checked): https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute/2019/544/fin@ — §30.
- PRH trademark fees: https://prh.fi/en/price-lists/trademark_fees/fees_for_trademark_applications.html
- EUIPO fees: from `docs/business/paperwork-checklist.md` (read 16 Oct 2026); euipo.europa.eu returned 403 on 3 Nov 2026.
- Not read here: CJEU C-5/08 *Infopaq*; Trade Secrets Act 595/2018; the Nice classification class headings (lawyer or trademark attorney to confirm the wording).
