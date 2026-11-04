# 08 — Risk register

> **Not legal, insurance or financial advice.** A planning register for the founder, lawyer, accountant and an insurance broker, written 3–5 November 2026 from the repository (`CLAUDE.md`, `docs/compliance/*`, `docs/business/*`, `legal/*`) and the sources in 01–07. Likelihood and impact are judgements for prioritising, not measurements. Insurance products and prices must come from insurers' quotes; none were requested.

Scale: **L** likelihood and **I** impact, 1 (low) – 5 (high).

| # | Risk | L | I | Owner actions | Insurance / cover |
|---|---|---|---|---|---|
| 1 | **Courier misclassification**: couriers held to be employees (Platform Work Directive presumption, national law planned from 2 Dec 2026; Supreme Administrative Court on Wolt couriers, May 2025, per the paperwork checklist) → back pay, pension and insurance contributions, penalties | 4 | 5 | Decide the model before launch (employ part-time, or keep freelancers genuinely free); lawyer review of `legal/courier_agreement.md` (05 §5.1); keep no auto-assignment, no rating-based pay or sanctions; document human review | If employing: **statutory accident and occupational disease insurance**, TyEL, unemployment insurance (compulsory). If freelance: require couriers' own accident and liability cover and check it at onboarding |
| 2 | **Courier road accident** during a delivery (injury to the courier or a third party, damage to property) | 3 | 5 | Safety rules in the agreement; vehicle type recorded; no time pressure in the app (no penalties for slowness); incident reporting | Courier's own accident insurance (freelance) or statutory accident insurance (employed); **motor liability insurance** is compulsory for mopeds and cars (the vehicle owner's); Malvoya's **general liability** policy checked for its "contractor" exclusions; consider a group accident policy for freelance couriers |
| 3 | **Goods lost or damaged in transit**, or delivered to the wrong person | 3 | 2 | Delivery proof (photo or in person) is built; clear rules in seller and courier terms on who bears the loss; claim process | **Goods-in-transit** (kuljetusvakuutus) or an extension to liability insurance |
| 4 | **Product liability and unsafe products** sold by shops (cosmetics reactions, children's clothing cords, nickel in jewellery) | 2 | 4 | Publishing rules and recalls are built (`catalog/publish.ts`, `/admin/recalls`); seller indemnity in the seller terms (05 §5.2); Safety Gate contact point (`docs/compliance/apparel-beauty.md`) | **Business and product liability insurance** (toiminnan ja tuotevastuuvakuutus) with marketplace activity declared |
| 5 | **Personal data breach** (database, Cloudinary photos of doors, seller tax IDs) | 2 | 5 | Keep the security controls in `CLAUDE.md` (MFA for admins, encryption of TINs, scrubbing); make the GitHub repository private; secrets backup and rotation (03 §6); breach procedure with the 72-hour notice (06); DPIA | **Cyber insurance** (incident response, data restoration, notification costs, third-party claims, possibly regulatory defence where insurable) |
| 6 | **GDPR non-compliance** (courier location tracking without a DPIA, missing DPAs, retention TODO for 6/10-year records) | 3 | 4 | DPAs accepted and recorded (05 §4); DPIA before launch; build the retention job (`docs/compliance/data-transparency-report.md` §8); decide on a DPO | Cyber policy with privacy-liability cover; **legal expenses** insurance |
| 7 | **Consumer-law enforcement** (KKV / Consumer Ombudsman): pre-contract information, withdrawal function, pricing, trader identity missing while placeholders remain | 2 | 3 | Fill group A placeholders (07); lawyer review of customer terms; keep the withdrawal function and Omnibus price rules | Legal expenses insurance (business disputes; check exclusions for regulatory matters) |
| 8 | **Platform duties** (DSA notice-and-action, P2B notice periods, DAC7 reporting by 31 January) | 2 | 3 | Calendar (06); DAC7 export and reminders are built; `DATA_ENCRYPTION_KEY` set and backed up | — (compliance) |
| 9 | **Loss of control of accounts or keys** (founder's personal account locked, lost Android upload key, lost `DATA_ENCRYPTION_KEY`, Stripe account frozen) | 3 | 5 | Move every account to the company with 2FA and a recovery kit (03 §4–6); Play App Signing; yearly recovery test | Cyber insurance (some cover social-engineering fraud; check) |
| 10 | **IP ownership gap**: code and brand still owned personally, AI-generated parts without copyright, third-party licence breaches, someone else using "Malvoya" (`malvoya.com` is not ours) | 3 | 4 | IP assignment (03 §2); contributor assignments; licence scan; trademark search and filing; check the `malvoya.com` holder | **IP / media liability** endorsement on liability or cyber cover (for claims that Malvoya infringes, e.g. sellers' photos, music in drops) |
| 11 | **Founder illness or absence** (single founder, single board member) | 2 | 5 | Deputy board member with written instructions (01 §4); emergency kit (03 §6); documented operations (`docs/`) | **Personal accident and sickness insurance** for the founder; YEL also sets sickness benefits (paperwork checklist §16) |
| 12 | **Director liability** once outsiders hold shares (claims against board members for breaching the Companies Act or articles, OYL ch. 22 §1) | 2 | 4 | Board minutes for major decisions; conflicts handled by the deputy (OYL ch. 6 §4); follow the shareholders' agreement | **D&O insurance** (johdon vastuuvakuutus) when the first investor or outside board member joins |
| 13 | **Payment and fraud risk** (chargebacks, stolen cards, payouts exceeding the charge "paid from Malvoya's balance", seller fraud) | 3 | 3 | Stripe Radar rules; System → attention checks; payout hold of 15 days for stores; lawyer check of the payment flow (05 §5.2 item 2) | Cyber/crime cover for fraud where available |
| 14 | **Tax errors** (VAT on marketplace and delivery fees, VAT-agent questions, transfer of IP, YEL level) | 3 | 3 | Accountant from day one; written VAT position on the fee model | Professional indemnity of the accountant (theirs) |
| 15 | **Investor terms that remove control** (participating preferences, full ratchet, investor-majority board early) | 2 | 5 | Term-sheet checklist (04 §3); lawyer on every round; A/B shares and clause 13 of the articles (02) | — |
| 16 | **Contract disputes with shops or couriers** | 3 | 2 | Clear terms, statements of reasons, internal complaints; mediation clause | **Legal expenses insurance** (oikeusturvavakuutus) for business disputes |
| 17 | **Hosting outage or data loss** (Render, single region) | 2 | 3 | Backups (PITR 3/7 days by plan); restore test; status page; maintenance message switch (`MAINTENANCE_MESSAGE`) | Cyber insurance business-interruption cover |
| 18 | **Running out of money** before traction (`docs/business/fundraising-plan.md`) | 3 | 5 | Low fixed costs; grants after registration (Business Finland, ELY); staged rounds | — |

## Insurance summary (for a broker)

| Policy | When | Notes for the quote |
|---|---|---|
| Business and product liability (toiminnan vastuu- ja tuotevastuuvakuutus) | Before the first real order | Declare: online marketplace for clothing and beauty, couriers as freelancers or employees, live video, Finland only; ask about contractor and "goods in care, custody and control" exclusions |
| Goods in transit (kuljetusvakuutus) | Before the first delivery | Value per order (items up to the 100 000 € price cap exist in imports, but typical orders are small); define who owns goods during delivery |
| Cyber | Before Stripe live | Incident response, data restoration, notification costs, third-party privacy claims, business interruption, social engineering |
| Legal expenses (oikeusturva) | With liability | Business disputes with sellers, couriers, suppliers |
| Statutory accident and occupational disease insurance, TyEL, unemployment insurance | Before the first employee works | Compulsory for employees |
| YEL (founder's pension) | Within 6 months of starting, if the thresholds apply | 01 §5, 06 |
| Founder's personal accident/sickness | At founding | Key-person risk |
| D&O (johdon vastuuvakuutus) | When investors or outside board members join | Investors usually require it in the shareholders' agreement |
| Group accident cover for freelance couriers (optional) | If freelance | Check that it does not become an employment indicator; the courier still buys their own cover |

## Sources
- Repository documents read 3 Nov 2026: `CLAUDE.md`, `docs/business/paperwork-checklist.md` (insurance, couriers, YEL), `docs/business/fundraising-plan.md`, `docs/compliance/litigation-risk-shield.md`, `docs/compliance/records-of-processing.md`, `docs/compliance/data-transparency-report.md`, `docs/compliance/apparel-beauty.md`, `legal/*.md`.
- Finlex open data, OYL 624/2006 consolidated `fin@20240652` (read 3 Nov 2026): ch. 6 §4, ch. 22 §1.
- No insurer pages or quotes were read.
