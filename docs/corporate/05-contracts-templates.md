# 05 — Contract outlines: employment, contractors, NDA, processor agreements, sellers and couriers

> **Not legal advice.** Outlines for a Finnish lawyer to turn into contracts, written 3–5 November 2026. The Employment Contracts Act 55/2001 (työsopimuslaki) was read from its **original** text on Finlex open data on 3 Nov 2026; later amendments (for example to probation and non-compete rules) are named where known but **must be checked in the consolidated version**. Copyright Act references: consolidated `fin@20230263`, read 3 Nov 2026. Processor terms were **not** re-read for this pack: the "where to accept" notes are what to look for, and each must be confirmed in the provider's current documents.

## 1. Employment contract (työsopimus), Finnish law

### 1.1 First: which collective agreement applies?
- An employer must follow at least the **generally binding collective agreement** (yleissitova työehtosopimus) of its field for the work the employee does; a contract term that conflicts with it is void and replaced by the agreement's term (Employment Contracts Act ch. 2 §7, read 3 Nov 2026).
- **Action:** for each role, look up the generally binding agreements in the official collective-agreement service (Finlex, confirmed by the board for the confirmation of general applicability) and pick the one matching the work: for example commerce/retail work, ICT/software work, or transport/delivery work for couriers. If several could apply, the lawyer decides (the employer's main line of business usually matters).
- The written statement of terms must name the applicable collective agreement (ch. 2 §4, item 7 in the original text).

### 1.2 Key clauses
1. Parties; start date; fixed-term (needs a justified reason) or indefinite.
2. Place of work; remote work rules.
3. Duties and title.
4. **Probation** (koeaika): the original Act allowed at most four months; the Act was later amended to allow up to **six months** (verify in force). In a fixed-term contract under eight months, at most half its length (ch. 1 §4 as in the text read).
5. Pay, pay period, benefits; the collective agreement's minimums.
6. Working time (Working Hours Act 872/2019) and annual holiday (Annual Holidays Act 162/2005) — not re-read here.
7. Notice periods (by the Act or the collective agreement).
8. **IP:** software made in the course of employment passes to the employer by law (Copyright Act §40 b), **but designs, texts, photos, music and other works do not**: add an express assignment of all work results, with the right to modify and transfer onward (Copyright Act §28) and a waiver of moral rights as far as allowed (§3). Inventions: the Act on the Right in Employee Inventions 656/1967 (not re-read) applies.
9. **Confidentiality and trade secrets** during and after employment (Trade Secrets Act 595/2018, not re-read).
10. **Non-compete** (kilpailukieltosopimus): allowed only for a particularly weighty reason. Since 2022 the Act requires the employer to **pay compensation** for the restriction period and limits its length (the amendment in force 1 Jan 2022; verify the current rules: the amounts and maximum period). Use only for key people.
11. **Data protection in working life:** couriers or staff whose location is tracked fall under the Act on the Protection of Privacy in Working Life 759/2004 (not re-read): purpose limitation, information duties and, at 20+ employees, cooperation procedures before introducing monitoring.
12. Equipment, phone and bike/vehicle rules; expenses.
13. Statutory insurances in place before the first day (accident insurance, TyEL, unemployment insurance) and the employer register when it applies (01 §6.5).

### 1.3 If couriers are employed
- Hourly part-time contracts with a guaranteed minimum or "zero-hour" variable hours: the Act has rules on variable working time (lawyer).
- The current dispatch model (first to accept wins, no auto-assignment) and the transparent pay formula can stay, but pay must meet the collective agreement.
- The courier agreement in `legal/courier_agreement.md` is then replaced by an employment contract plus a work-instruction document; the courier app's terms text changes accordingly.

## 2. Contractor / freelancer agreement (toimeksiantosopimus)

Used for designers, developers, photographers, marketing help.

1. Parties: the contractor's legal name and **Y-tunnus**; check the contractor is in the **prepayment register** (otherwise the company must withhold tax from the payment) and the VAT register.
2. Scope, deliverables, schedule, acceptance.
3. Fee, invoicing (VAT), payment term (e.g. 14 days).
4. **IP assignment:** all results and rights pass to the company on payment (no automatic transfer exists for contractors), with the right to modify and transfer onward (Copyright Act §28) and a moral-rights waiver as far as allowed (§3). The contractor lists any pre-existing material and open-source components they bring, with licences; the company gets a perpetual licence to the contractor's pre-existing tools that are embedded.
5. **Confidentiality** (survives termination; trade secrets indefinitely).
6. **Personal data:** if the contractor sees production data (support, development with real data), add a **data processing agreement** (GDPR Art. 28). Prefer giving contractors test data only.
7. Security: company accounts only, 2FA, no copies on personal devices, return/delete at the end.
8. No subcontracting without written consent.
9. **Independence:** the contractor decides how and when to work, uses their own tools, may work for others (to avoid being reclassified as an employee).
10. Liability cap (e.g. the fees paid in 12 months), except for confidentiality, IP and data breaches.
11. Term and termination; return of material.
12. Finnish law; forum.
13. **Contractor's Obligations Act** (tilaajavastuulaki 1233/2006, not re-read): applies only in certain sectors and above value thresholds (mainly where contractors' workers work at the client's premises); ask the lawyer whether it applies to any courier or warehouse arrangement.

## 3. NDA

### 3.1 The existing `legal/Malvoya_NDA.docx` (read 3 Nov 2026): what to change

| Issue | Why | Fix |
|---|---|---|
| Names "Malvoya Oy" and "Registered Address: Helsinki" | The company does not exist; the name's availability and the address are unknown | `[COMPANY NAME] Oy`, `[Y-TUNNUS]`, `[ADDRESS]` until registration |
| Describes "infrastructure (Firebase / Google Cloud)", "5 %–10 % commission", "€3.00 guaranteed base rate", "dispatch algorithms" | Out of date: hosting is Render Frankfurt with Postgres; commission is 0 % since 2.13.0; courier pay follows `utils/courierPay.ts` | Describe categories of information, not numbers that change |
| One-way (only Malvoya discloses) | Partners and investors prefer mutual NDAs and refuse one-sided ones | Offer a mutual version |
| Liquidated damages €25 000 / €75 000 / €150 000 "not a penalty" | "Penalty vs. liquidated damages" is a common-law idea; in Finland a contractual penalty (sopimussakko) can be adjusted by a court if unreasonable (Contracts Act §36, not re-read); very high amounts make counterparties refuse to sign | Proportionate penalty, or none plus damages and injunction |
| 24-month non-solicitation incl. employees and couriers | May conflict with competition law and, for individuals, with employment rules; heavy for investors | 12 months, key employees only |
| "Finnish Act on Electronic Signatures (14/2003)" | That act is believed to have been replaced by the Act on Strong Electronic Identification and Electronic Trust Services 617/2009 (verify) | Refer to eIDAS and the current Finnish act |
| Investor tick-box | Most venture investors do not sign NDAs | Use the NDA for partners, contractors, suppliers; for investors share a deck and demo, not code |

### 3.2 Outline of a mutual NDA
1. Parties; purpose (evaluation of a specific cooperation).
2. Definition of confidential information (marked or obviously confidential); exclusions (public, already known, independently developed, received lawfully).
3. Use only for the purpose; need-to-know disclosure to advisers bound by confidentiality.
4. No personal data shared unless a separate agreement covers it.
5. Compelled disclosure: notice where lawful.
6. Return or destruction on request; backups exception.
7. Term: 2–3 years; trade secrets as long as they remain secret.
8. No licence, no obligation to proceed.
9. Remedies: damages and injunction; optional proportionate contractual penalty.
10. Finnish law; Helsinki District Court or arbitration.

## 4. Processor agreements (DPAs)

GDPR Art. 28 requires a written contract with each processor. Most providers offer a standard DPA that is part of their terms or accepted by a click; some need a signature. The list follows `docs/compliance/records-of-processing.md`.

| Provider (role) | Data | What to look for / how to accept (verify in current docs) | Transfer basis to record |
|---|---|---|---|
| **Render** (hosting, Postgres, logs, backups; Frankfurt) | All service data | Render's Data Processing Addendum, referenced from its terms; check whether a countersigned copy can be requested | Data at rest in DE; US support access: SCCs or EU–US Data Privacy Framework (DPF) |
| **Stripe** (payments processor; independent controller for KYC/AML and fraud) | Payment, order metadata, payout account data | Stripe's DPA is part of the Stripe Services Agreement accepted at live activation; save a PDF of the version accepted | DPF / SCCs in Stripe's DPA |
| **Google Firebase / Google Cloud** (Auth, FCM, Crashlytics, App Distribution) | Phone numbers, tokens, crash data | Firebase/Google Cloud data processing terms: accept them in the Firebase/Google Cloud console's privacy or legal settings for the company organisation; add the company's privacy contact there | DPF + SCCs |
| **Cloudinary** (images, videos, audio, private delivery photos) | Uploaded media incl. door photos | Cloudinary's DPA (online; check whether it must be signed); choose an EU storage region if offered | DPF or SCCs |
| **LiveKit** (live-shopping video, only if switched on) | WebRTC media, IP addresses, first names | LiveKit Cloud's DPA (check legal pages or ask support); region | SCCs / DPF |
| **Email provider** `[EMAIL PROVIDER]` (transactional email) and `[MAILBOX PROVIDER]` (team mailbox) | Email addresses, message content | Business plans usually include a DPA accepted in the admin console; choose EU data location if offered | Per provider |
| **OpenRouteService / HeiGIT gGmbH** (street routes, only if switched on) | Two coordinate pairs per route (courier/shop/home positions) | Check HeiGIT's terms for a processor agreement; if none is offered, ask for one or self-host OpenRouteService, and record the assessment (EU provider; minimal data) | None needed (EU) |
| **Sentry** (error reports, only if switched on) | Scrubbed error events, user id | Sentry's DPA (accepted in the organisation's legal settings); choose the **EU data region** | DPF / SCCs |
| **Twilio** (SMS codes, only if switched on) | Phone numbers, code texts | Twilio's DPA, part of its terms | DPF / SCCs |
| **Redis provider** `[REDIS PROVIDER]` (only if `REDIS_URL` set) | IP-keyed counters, session cache | If Render Key Value, Render's DPA covers it | — |
| **Accounting firm** | Bookkeeping data, staff and seller payment data | Processor clause in the accounting engagement letter | EU |
| **AI tools used in operations** (if any user data is ever pasted into them) | Avoid entirely, or business plan with a DPA | — | — |

**How to record each one (DPA register; keep with the records of processing):**

| Provider | Contracting entity | DPA version / date | How accepted (click, signature, part of terms) | Accepted by | Sub-processor list URL and notification method | Region chosen | Transfer mechanism | Copy saved at | Next review |
|---|---|---|---|---|---|---|---|---|---|

Steps: (1) accept only from the **company** account; (2) download the PDF of the version accepted; (3) subscribe to sub-processor change notices; (4) update `docs/compliance/records-of-processing.md` and `legal/privacy_policy.md` with the regions and safeguards (the placeholders in 07); (5) review yearly (06).

Separate controllers are not processors: Stripe (for KYC/AML), Google Sign-In, Apple, the OpenStreetMap Foundation and the stores themselves. The seller terms should contain a short controller-to-controller data clause (§5.2).

## 5. Seller and courier agreements (`legal/`): improvements for the lawyer

These texts exist and are detailed. The lists below are **edits to consider**; nothing in `legal/` was changed.

### 5.1 Courier agreement (`legal/courier_agreement.md`)

1. **Choose the model first** (08 risk 1). The text assumes independent couriers; the Platform Work Directive presumption of employment (national law planned from 2 Dec 2026, per the paperwork checklist) and the Supreme Administrative Court's 2025 Wolt ruling make this the largest risk. If employing, replace it with an employment contract (§1.3).
2. **Insurance clause:** require couriers' own accident insurance, third-party liability insurance and, for mopeds/cars, the compulsory motor liability insurance; check at onboarding and on renewal; state what happens without it.
3. **Goods in transit:** who bears loss of or damage to goods while carried; claim process; cap; Malvoya's own goods-in-transit cover (08).
4. **Accidents and incidents:** how to report, what Malvoya does, emergency contact.
5. **Self-billing:** if Malvoya issues the couriers' invoices on their behalf (monthly statement), the VAT Act's self-billing rules require an agreement and certain invoice content (accountant to confirm); couriers under the VAT threshold are not VAT-registered.
6. **Tax status:** check prepayment-register status at onboarding; light-entrepreneur (invoicing service) couriers; what Malvoya does if a courier is not in the register (withholding).
7. **Platform Work Directive transparency** (beyond what §4 already says): the information on automated monitoring and decision systems, the right to an explanation and human review within the Directive's deadlines, the prohibited data (emotional state, private conversations, off-duty data), data portability, and consultation of representatives — align with the Finnish act when adopted.
8. **Data protection:** a clear confidentiality clause for customers' names, addresses and door codes; ban on copying or keeping them after the job; reference to the DPIA.
9. **Liability:** limitation of liability both ways; courier indemnity for intentional misconduct only.
10. **Placeholders:** `[VERIFICATION METHOD]` (e.g. a strong-identification service; documents never stored in the app), `[COURIER PAY PARAMETERS…]` (copy the current env values from System → pricing), `[NOTICE PERIOD]` (suggest 15 days, the same as §7a), `[14]` days' notice for termination, `[Helsinki District Court]`.
11. **Assignment clause:** Malvoya may transfer the agreement to a successor company (needed for investment and M&A).
12. **Finnish version:** the text is English with a Finnish title; publish a full Finnish text, stating which language prevails.
13. **Branding/equipment:** keep optional; mandatory uniforms and equipment are employment indicators.
14. **Prohibited items and safety rules** (no alcohol or age-restricted goods are sold today; say so).

### 5.2 Seller terms (`legal/vendor_terms.md`)

1. **Role of Malvoya:** state clearly that the seller is the seller of record and Malvoya is an intermediary (marketplace), and who issues the receipt or invoice to the buyer (business buyers may need a VAT invoice). Accountant: the VAT treatment of the delivery fee and any service fees Malvoya charges.
2. **Payment flow:** confirm with the lawyer that Malvoya does not provide a licensed payment service: Stripe Connect transfers to the seller's own Stripe account, but `CLAUDE.md` notes that payouts not covered by the charge are "paid from Malvoya's balance". Document the flow and the legal basis.
3. **Liability and indemnity:** a limitation of Malvoya's liability, and a seller indemnity for unsafe or counterfeit products, recalls, IP claims and wrong product information.
4. **P2B Regulation:** add the description of data access (Art. 9: what data Malvoya and sellers get), any differentiated treatment (Art. 7), and ranking parameters stay in §7 (keep `[UPDATE IF PAID PLACEMENT IS INTRODUCED.]` as an internal reminder, not published text).
5. **Mediator** `[MEDIATOR]`: P2B Art. 12 asks platforms to name mediators; small enterprises are exempt (paperwork checklist §14), but the text promises one. Name a mediation service (lawyer to suggest, e.g. a chamber-of-commerce mediation institute) or remove the promise.
6. **Controller-to-controller data clause:** the seller may use the buyer's order data only to fulfil the order, keep it secure and delete it when no longer needed; no marketing to buyers without consent.
7. **Pickup hold time `[72]` hours:** must match the code (`PICKUP_HOLD_HOURS`, default 72) and the customer terms.
8. **Forum:** add the court (or arbitration) for business disputes.
9. **Assignment, force majeure, notices, entire agreement, severability.**
10. **Language:** Finnish version, prevailing language.
11. **Commission:** if a commission is ever introduced, the 15-day notice and the seller's right to terminate already exist (§6); keep the code's `commissionRate` at 0 until then (`CLAUDE.md`).
12. **Company details:** `[COMPANY LEGAL NAME]`, `[Y-TUNNUS]`, `[DATE OF PUBLICATION]` (07).

### 5.3 Customer terms (`legal/terms_of_service.md`), short list
- Decide `[OR: "Malvoya arranges and pays for courier pick-up"]` for returns (line 82): this is a cost decision.
- Fill company identity, address and phone (line 9); consumer law requires the trader's identity and contact details before the contract.
- Add the consumer dispute route (Consumer Disputes Board, kuluttajariitalautakunta) and the EU ODR reference if still required (lawyer).

## 6. Offboarding checklist (staff and contractors)
Remove from GitHub, Render, Firebase, Stripe, Cloudinary, stores, email, password manager; rotate shared secrets; collect devices; confirm deletion of copies; update the account register (03 §4.3).

## 7. Sources
- Finlex open data, Employment Contracts Act 55/2001 (original text), ch. 1 §4, ch. 2 §§4, 7 (read 3 Nov 2026): https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute/2001/55/fin@
- Finlex open data, Copyright Act 404/1961 consolidated `fin@20230263`, §§3, 27, 28, 40 b (read 3 Nov 2026).
- `legal/Malvoya_NDA.docx`, `legal/courier_agreement.md`, `legal/vendor_terms.md`, `legal/terms_of_service.md`, `docs/compliance/records-of-processing.md`, `docs/business/paperwork-checklist.md` (all read 3 Nov 2026).
- Not re-read: GDPR Art. 28; P2B Regulation 2019/1150; the Platform Work Directive 2024/2831; Working Hours Act; Annual Holidays Act; Act on the Protection of Privacy in Working Life; Trade Secrets Act; Contracts Act §36; Act 617/2009; each provider's current DPA.
