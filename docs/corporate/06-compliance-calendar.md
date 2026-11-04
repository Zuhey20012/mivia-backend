# 06 — Yearly compliance calendar

> **Not legal, tax or accounting advice.** A planning calendar for the founder and the accountant, written 3–5 November 2026. It assumes the **financial year is the calendar year** and a **monthly VAT period**; change the dates if either differs. Official dates move when they fall on a weekend or holiday (vero.fi: the next business day). Confirm every date in OmaVero, the PRH e-service and each provider's account before relying on it.

## 1. Every month

| When | What | Basis / source | Who |
|---|---|---|---|
| 12th | **VAT return and payment** for the month two months earlier (e.g. June → 12 August) | vero.fi, "Verokauden muutos" examples (updated 5 Dec 2024) | Accountant |
| 12th | **Employer contributions** (withholding, health insurance contribution) for the previous month — only once employing | Act on assessment procedure for self-assessed taxes 768/2016 (general due date the 12th; secondary summary, not re-read) | Accountant |
| Within 5 days of each pay day | **Incomes Register** report of wages — only once employing | paperwork checklist | Accountant |
| Date on the decision | **Prepayment of corporate income tax** (ennakkovero) instalments | Prepayment decision in OmaVero | Company |
| First week | Bookkeeping material to the accountant (Stripe reports, payouts, refunds, invoices, Render/Apple/Google receipts) | Accounting Act | Founder |
| Monthly | Check the admin panel → System for blockers and attention items (failed payouts, refunds, DAC7 data missing) | `CLAUDE.md` | Founder |

**If quarterly VAT is chosen** (turnover under 100 000 €): returns on 12 May, 12 August, 12 November, 12 February. **If yearly** (under 30 000 €): one return for the calendar year, due in early the following year (end of February per secondary sources; verify in OmaVero).

## 2. The year, month by month

| Month | Deadline / task | Basis | Who |
|---|---|---|---|
| **January** | **31 Jan: DAC7 report** for the previous year to Vero via Ilmoitin.fi, also when there is nothing to report; export from admin → DAC7 | Council Directive (EU) 2021/514; vero.fi DAC7 (paperwork checklist, read 16 Oct 2026) | Founder + accountant |
| January | Annual information returns not covered by the Incomes Register (accountant to list) | vero.fi | Accountant |
| January | Review the year's DAC7 reminders and missing seller tax data | `sellers/taxReminders.ts` | Founder |
| **February** | Calendar-year VAT return (only if a yearly period is chosen) | vero.fi (verify) | Accountant |
| February | **Insurance renewal review** (or on each policy's own date): liability, cyber, legal expenses, goods in transit | Policies `[POLICY RENEWAL DATES]` | Founder |
| **March** | Board approves the draft **financial statements** (tilinpäätös) and annual report | Accounting Act ch. 3 §6: financial statements prepared within **four months** of the year's end as currently in force (the 1997 original text read said three; accountant to confirm) — so by **30 April** | Board + accountant |
| March | **Quarterly legal-text review** (Q1): changes in law, new features, retention periods; publish via admin → Legal with ≥ 15 days' notice for seller terms and courier agreement | `CLAUDE.md` (legal versions) | Founder + lawyer |
| **April** | **30 Apr: corporate income tax return** (form 6B) in OmaVero: within 4 months after the end of the financial year's last month | vero.fi corporate deadlines (updated 19 Dec 2025, read 3 Nov 2026) | Accountant; board signs off |
| April | Board signs the financial statements | Accounting Act ch. 3 §7 | Board |
| **May** | Annual **GDPR review**: records of processing (`docs/compliance/records-of-processing.md`), privacy policy and `legal/data_explained.md`, DPA register (05 §4), sub-processor changes | GDPR Art. 30 | Founder |
| May | Annual **DPIA review** for courier location and job offers; redo when the feature changes | GDPR Art. 35 | Founder (+ lawyer) |
| **June** | **By 30 Jun: annual general meeting** (varsinainen yhtiökokous): adopt the accounts, decide on profit, discharge from liability, board | OYL ch. 5 §3 (read 3 Nov 2026) | Shareholders (written decision while sole owner, OYL ch. 5 §1) |
| June | Quarterly legal-text review (Q2) | — | Founder + lawyer |
| **July–August** | **File the financial statements with PRH within two months of the AGM adopting them** (OYL ch. 8 §10); PRH charges a late-filing fee when filed more than **eight months** after the year's end, i.e. after **31 August** | OYL ch. 8 §10; prh.fi late-submission fee page (search result 3 Nov 2026) | Accountant |
| August | **Annual review of trade register details** (PRH made it mandatory from 2026; fees possible from 2027 — per the PRH-related search results of 3 Nov 2026, verify) | prh.fi | Founder |
| **September** | Quarterly legal-text review (Q3) | — | Founder + lawyer |
| September | **Security week:** rotate secrets (JWT, Stripe, Cloudinary, Firebase service account if needed), test recovery codes and backup hardware keys, check 2FA on every account, review the account register and remove old users | 03 §5–6 | Founder |
| **October** | **YEL income review** with the pension company (also whenever income changes materially) | paperwork checklist §16 | Founder |
| October | Budget and prepayment check: ask Vero to adjust corporate prepayments if profit differs | OmaVero | Accountant |
| **November** | Insurance quotes for the next year; D&O once investors join | 08 | Founder |
| November | Quarterly legal-text review (Q4) | — | Founder + lawyer |
| **December** | Year-end: stock-take of open refunds and payouts, cut-off for bookkeeping, plan the next financial statements | Accounting Act | Founder + accountant |
| December | Check beneficial owners and the shareholder register are up to date | AML Act 444/2017; OYL ch. 3 §15 | Board |

## 3. Anniversary dates (fill in once known)

| Item | Date | Notes |
|---|---|---|
| Apple Developer Program renewal | `[ENROLMENT DATE]` + each year | 99 USD/year; if it lapses, apps are removed from the App Store |
| Google Play developer account | one-time fee; keep contact details and D-U-N-S data current | Google sends verification requests |
| Domain renewals `[DOMAIN].fi`, `[DOMAIN].com` | `[EXPIRY DATES]` | Auto-renew on, card valid, registrar lock |
| TLS certificates | automatic on Render | Monitor |
| `/.well-known/security.txt` Expires | rolls automatically 180 days ahead | `CLAUDE.md`; check `SECURITY_CONTACT` |
| Stripe: representative, owners, bank details | each change + yearly | Respond to Stripe KYC requests at once, or payouts stop |
| D-U-N-S record | yearly | Must match the trade register exactly |
| Insurance policies | `[POLICY DATES]` | 08 |
| Trademark (PRH) | **10 years from the filing date** `[FILING DATE]`; renew at the earliest 1 year before expiry; PRH reminds at least 6 months before; late renewal within 6 months after expiry costs 320 € | Trademarks Act 544/2019 §30; prh.fi fees (read 3 Nov 2026) |
| EU trademark (if filed) | 10 years from filing | EUIPO |
| Lawyer review of company documents | yearly, and before every round | 04 |

## 4. Event-driven deadlines

| Event | Deadline | Basis |
|---|---|---|
| Founding agreement signed | file for registration within **3 months** | OYL ch. 2 §8 |
| Starting business as a YEL entrepreneur | YEL insurance within **6 months** | paperwork checklist |
| Change of board, managing director, articles, share capital, address | change notification to PRH without delay; an articles change must be filed without delay and cannot be implemented before it is registered | OYL ch. 5 (articles amendment section, read 3 Nov 2026); PRH |
| Change of beneficial owners | update without delay | AML Act 444/2017 |
| Share transfer received by the board | redemption-clause notice within **1 month**; redemption claim within **2 months**; consent answer within **2 months** or consent is deemed given | OYL ch. 3 §§7–8 |
| Personal data breach | notify the Data Protection Ombudsman within **72 hours** when required | GDPR Art. 33 |
| New processor or sub-processor | DPA before use; update records and privacy policy | GDPR Art. 28, 30 |
| Change to seller terms or courier agreement | publish ≥ **15 days** before effect | P2B Art. 3; `CLAUDE.md` |
| First employee | employer register when a regular employer; statutory insurances before day 1; Incomes Register within 5 days of pay | 01 §6.5 |
| National Platform Work Directive law in force (planned 2 Dec 2026) | review courier model and agreement | paperwork checklist §11 |
| 10+ staff or > 2 M€ turnover | European Accessibility Act duties start applying | paperwork checklist §21 |
| Retention end of order records (6 years) and DAC7 (10 years) | purge job still a TODO | `docs/compliance/data-transparency-report.md` §8 |

## 5. Sources
- Finlex open data, OYL 624/2006 consolidated `fin@20240652` (read 3 Nov 2026): ch. 2 §8, ch. 3 §§7–8, 15, ch. 5 §§1, 3, ch. 8 §10.
- Finlex open data, Accounting Act 1336/1997 (original text) ch. 3 §§6–7 and ch. 2 §10 retention (read 3 Nov 2026; amendments not checked).
- Finlex open data, Trademarks Act 544/2019 §30 (read 3 Nov 2026).
- vero.fi, important dates and deadlines for corporate taxpayers (updated 19 Dec 2025): https://vero.fi/en/businesses-and-corporations/important_dates_and_deadlines_for_corporate_taxpayers/
- vero.fi, Verokauden muutos (updated 5 Dec 2024): https://vero.fi/yritykset-ja-yhteisot/verot-ja-maksut/arvonlisaverotus/ilmoitus-ja-maksuohjeet/verokauden-muutos/
- prh.fi trademark fees (read 3 Nov 2026).
- `docs/business/paperwork-checklist.md` (DAC7, YEL, Apple, Google, read 16 Oct 2026).
- **Could not verify:** the yearly VAT due date, the mandatory annual trade-register review and its fee, the employer-contribution due date (secondary sources only).
