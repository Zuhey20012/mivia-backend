# 07 — Placeholder fill list

> **Not legal advice.** An inventory for the founder, lawyer and accountant, made on 3 November 2026 by searching `legal/`, `docs/`, `web/src` and the backend's email and HTML templates for `[PLACEHOLDER]`-style tokens (upper-case bracketed words, bracketed numbers such as `[72]`, and bracketed alternatives). Line numbers are those of 3 November 2026; they move when files are edited, so search for the token if a line does not match. **Never fill a value that is not real**: the company name, business ID and addresses come only from the trade register once the company exists.

## How to use it
1. Fill group A the day the trade-register extract arrives; groups B–C as each account or policy exists; group D after the founder (and lawyer) decide.
2. Edit `legal/*.md`, then publish each text in admin → Legal (seller terms and courier agreement need ≥ 15 days' notice; `CLAUDE.md`). The admin System page shows a blocker while any text in force still contains `[PLACEHOLDERS]` (`backend/src/modules/admin/system.ts:136-145`).
3. Docs under `docs/` are internal; fill them for accuracy, they are not published.

## Not placeholders (leave as they are or delete before publishing)
- `legal/privacy_policy.md:5` and `legal/terms_of_service.md:5`: the editor's note "fill in the `[BRACKETED]` items" — remove the whole "Before publishing" note when publishing.
- `legal/ip_notice.md:54` "[LAWYER: confirm the thresholds and the suspension period.]" — a lawyer note; remove after review.
- `[LAWYER]` / `**[LAWYER]**` / `[verify …]` markers throughout `docs/compliance/` — review questions, not values.
- `backend/src/modules/admin/system.ts:141` — the regular expression that detects placeholders.
- `web/src` — **no placeholders found**. Note: the website shows no company identity at all; add the trader's name, Y-tunnus, address and contact to its legal/contact page after registration (a code edit, not done here).

---

## Group A — after registration (value from the trade register extract, virre.prh.fi)

| Token | File:line | What to fill | Source |
|---|---|---|---|
| `[COMPANY LEGAL NAME]` | `legal/account_deletion.md:5`, `legal/courier_agreement.md:9`, `legal/data_explained.md:5`, `legal/ip_notice.md:3`, `legal/privacy_policy.md:9`, `legal/terms_of_service.md:9`, `legal/vendor_terms.md:9` | Registered name exactly, e.g. "[NAME] Oy" | Trade register |
| `[Y-TUNNUS]` | same seven lines as above | Business ID (format 1234567-8; validated by the check digit in `stores/businessCheck.ts` logic) | Trade register |
| `[STREET ADDRESS]`, `[POSTCODE]`, `[CITY]` | `legal/privacy_policy.md:9` | Registered postal address | Trade register |
| `[ADDRESS]` | `legal/terms_of_service.md:9` | Same address | Trade register |
| `[COMPANY LEGAL NAME]`, `[Y-TUNNUS]`, `[COMPANY ADDRESS]` | `backend/src/modules/sellers/statements.ts:112` (the printable monthly seller statement HTML) | Company identity on statements | Trade register — **code edit** (better: read from env vars such as `COMPANY_LEGAL_NAME`, `COMPANY_BUSINESS_ID`, `COMPANY_ADDRESS`; not done here) |
| `[COMPANY LEGAL NAME]`, `[Y-TUNNUS]`, `[STREET ADDRESS]`, `[POSTCODE]`, `[CITY]` | `docs/compliance/records-of-processing.md:9` | Controller identity | Trade register |
| `[COMPANY LEGAL NAME]`, `[Y-TUNNUS]` | `docs/compliance/data-transparency-report.md:147`, `docs/play-data-safety.md:189` | Same | Trade register |
| `[DEVELOPER NAME AS SHOWN ON GOOGLE PLAY]` | `docs/play-data-safety.md:141` | The organisation name on the Play developer account (after the account moves to the company) | Play Console |
| Business ID, address, legal representative, email (blank lines) | `legal/Malvoya_NDA.docx` (party block) | Company identity; also **remove** the invented "Registered Address: Helsinki" and check the name | Trade register (see 05 §3.1) |
| `[DATE OF PUBLICATION]` | `legal/account_deletion.md:3`, `legal/courier_agreement.md:3`, `legal/data_explained.md:3`, `legal/privacy_policy.md:3`, `legal/terms_of_service.md:3`, `legal/vendor_terms.md:3` | The date the version takes effect (the effective date chosen in admin → Legal) | Publishing decision |

## Group B — after the email, domain and provider accounts exist

| Token | File:line | What to fill | Source |
|---|---|---|---|
| `[PHONE]` | `legal/terms_of_service.md:9` | Customer service phone number (consumer law expects a fast contact channel; a phone is common) | Company phone subscription |
| `[EMAIL PROVIDER]` | `legal/privacy_policy.md:96`; `legal/data_explained.md:131, 403, 533, 805`; `docs/compliance/records-of-processing.md:25`; `docs/compliance/data-transparency-report.md:138, 147`; `docs/play-data-safety.md:28` | Name and country of the transactional email provider used for `SMTP_*` | Provider contract / DPA (05 §4) |
| `[MAILBOX PROVIDER]` | `legal/privacy_policy.md:96`; `legal/data_explained.md:163, 565`; `docs/compliance/records-of-processing.md:26`; `docs/compliance/data-transparency-report.md:65, 138, 147` | Provider of the team mailbox receiving `SUPPORT_EMAIL` | Email provider contract |
| `[REGION]`, `[SAFEGUARD]` | `legal/data_explained.md:403, 805`; `docs/compliance/records-of-processing.md:25, 26, 29` | Data location of the email / mailbox / Redis provider and the transfer basis (EU = none needed; US = DPF or SCCs) | Provider DPA |
| `[SUPPORT EMAIL]` | `docs/play-data-safety.md:133, 153, 170`; `docs/play-store-listing.md:386`; `docs/play-store-release-checklist.md:60, 69` | Support address on the company domain (not @malvoya.com, which is not under the company's control) | Company email |
| `[PRIVACY MAILBOX]` | `docs/compliance/records-of-processing.md:12` | Privacy contact address (can be the same as support) | Company email |
| `[CLOUDINARY REGION]` / `[CLOUDINARY ACCOUNT REGION]` | `legal/data_explained.md:397, 799`; `docs/compliance/records-of-processing.md:21`; `docs/compliance/data-transparency-report.md:147` | Storage region of the Cloudinary account | Cloudinary account settings |
| `[LIVEKIT REGION]` | `legal/data_explained.md:400, 802`; `docs/compliance/records-of-processing.md:27`; `docs/compliance/data-transparency-report.md:147` | LiveKit Cloud region (or "self-hosted in …"); leave the row out if live shopping stays off | LiveKit account |
| `[SENTRY REGION]` / `[EU or US region]` | `legal/data_explained.md:401, 803`; `docs/compliance/records-of-processing.md:28`; `docs/compliance/data-transparency-report.md:147` | Sentry data region (EU recommended) | Sentry organisation settings |
| `[SENTRY RETENTION]` | `docs/compliance/records-of-processing.md:270` | Event retention of the Sentry plan | Sentry plan |
| `[REDIS PROVIDER]` | `docs/compliance/records-of-processing.md:29`; `docs/compliance/data-transparency-report.md:138` | Redis provider, only if `REDIS_URL` is set (else remove the row) | Render env |
| `[LOG RETENTION OF THE HOSTING PLAN]` / `[RENDER LOG RETENTION OF THE PLAN]` | `legal/privacy_policy.md:136`; `legal/data_explained.md:319, 721`; `docs/compliance/records-of-processing.md:270`; `docs/compliance/data-transparency-report.md:147` | Number of days Render keeps request logs on the plan in use | Render plan page |
| `[7]` (backup days) | `legal/privacy_policy.md:137`; `legal/account_deletion.md:39`; `legal/data_explained.md:331, 733`; `docs/compliance/data-transparency-report.md:147` | Point-in-time-recovery days of the database plan. **Check:** the records of processing say 3 days on Render's Hobby plan and 7 on Pro, so `[7]` is true only on Pro | Render database plan |
| `[7]` (confirmation days) | `docs/play-data-safety.md:153` | How fast email deletion requests are confirmed | Owner decision |
| `[TEST STORE ADDRESS]` | `docs/play-store-release-checklist.md:83` | Address of the store used by app reviewers | Test store set-up |

## Group C — after the bank and after the insurance

- **Bank:** no placeholder in the texts needs bank details. The bank account is a prerequisite for Stripe live, payouts and VAT payments (README step 8).
- **Insurance:** no placeholder exists today. Once policies exist, consider **adding** to `legal/courier_agreement.md` the insurance couriers must hold and any cover Malvoya provides (05 §5.1 item 2), and record `[POLICY RENEWAL DATES]` in the calendar (06).

## Group D — owner decisions (with the lawyer where marked)

| Token | File:line | Decision | Notes |
|---|---|---|---|
| `[72]` (hours to collect a pickup order) | `legal/terms_of_service.md:64`, `legal/vendor_terms.md:69` | Hold time for Reserve & collect | Must equal the code's `PICKUP_HOLD_HOURS` (default 72, `backend/src/config/env.ts:219`) |
| `[OR: "Malvoya arranges and pays for courier pick-up"]` | `legal/terms_of_service.md:82` | Who pays for returns: the customer, or Malvoya arranges and pays a courier | Cost decision; keep one wording |
| `[MEDIATOR]` | `legal/vendor_terms.md:101` (also mentioned in `docs/business/paperwork-checklist.md:111`) | Name a mediation service for sellers, or remove the promise | Lawyer (05 §5.2 item 5) |
| `[UPDATE IF PAID PLACEMENT IS INTRODUCED.]` | `legal/vendor_terms.md:87` | Internal reminder; delete before publishing (keep the rule in a checklist) | — |
| `[VERIFICATION METHOD]` | `legal/courier_agreement.md:27` | How identity, right to work and age are checked (e.g. a strong-identification service; documents not stored in the app) | Lawyer |
| `[COURIER PAY PARAMETERS: …]` | `legal/courier_agreement.md:47` | The current values: base 4,50 €, per km 1,10 €, minimum 6,50 €, road factor 1.3, ride-to-store free 2 km then 0,50 €/km, 5 free waiting minutes then 0,20 €/min up to 4,00 € — **these are the code defaults in `CLAUDE.md`; copy the live values from admin → System → pricing** | Must match Render env |
| `[NOTICE PERIOD]` | `legal/courier_agreement.md:47` | Notice before changing pay parameters (suggest ≥ 15 days, like the text's own §7a) | Lawyer |
| `[14]` (termination notice) | `legal/courier_agreement.md:73` | Days' notice when Malvoya ends a courier agreement | Lawyer (Platform Work Directive) |
| `[Helsinki District Court]` | `legal/courier_agreement.md:77` | Court for disputes (often the company's domicile court) | Lawyer; depends on domicile |
| `[3]` / `[12]` | `legal/ip_notice.md:54` | Repeat-infringer threshold: upheld notices within months | Lawyer (DSA Art. 23) |
| `[DPO NAME AND CONTACT, OR "not appointed" WITH THE REASONING]` | `docs/compliance/records-of-processing.md:11` | Whether a data protection officer is needed (courier tracking at scale) | Lawyer |
| `[FINANCIAL YEAR]` | `docs/compliance/data-transparency-report.md:195` | Financial year (calendar year recommended, 01 §2.2) | Founding agreement / articles |
| `[SEQUENCE NUMBER]` | `legal/Malvoya_NDA.docx` (document reference `MALVOYA-NDA-2026-[SEQUENCE NUMBER]`) | Numbering of signed NDAs | Internal register |

## Edits that the placeholders do not cover (listed, not made)

1. `backend/src/modules/sellers/statements.ts:112`: move the company identity to configuration (see group A).
2. Website (`web/src`): add company identity and contact details after registration.
3. Transactional emails (`backend/src/services/notificationDeliveryService.ts`): consider naming the company in the footer once registered (not a placeholder today).
4. `legal/Malvoya_NDA.docx`: rewrite the outdated business facts (05 §3.1).
5. `docs/play-store-launch.md:21` mentions a "commission" placeholder that no longer exists in `legal/` (commission is 0 % since 2.13.0); update that checklist line.
