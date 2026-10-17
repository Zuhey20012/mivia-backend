# Malvoya paperwork checklist (Finland and EU)

Prepared 17 October 2026. In the order to do it. Fees were read on 16 October 2026; check the official page before paying. This is a summary, not legal or tax advice. No company exists yet; never invent company names or business IDs.

## 1. Name and trademark check

- **What:** Search "Malvoya" in TMview (EU and national registers), the PRH trademark database and the trade register before registering the company, printing or buying a domain. A plain web search on 16 Oct 2026 found no other business using the name, but no register search has been done.
- **Why:** Avoid a forced rename after launch.
- **Where:** tmdn.org/tmview · prh.fi (trademark search) · ytj.fi (company names)
- **Cost:** Free
- **Time:** 1 day

## 2. Company form: Oy (osakeyhtiö)

- **What:** Oy is recommended over toiminimi: limited liability, room for investors and employee shares, and Apple's organisation account does not accept trade names. An Oy needs no minimum share capital (abolished in 2019). One founder can be the sole shareholder and board member; a deputy board member is required if the board has fewer than three members.
- **Why:** Liability for refunds, couriers and platform duties sits with the company, not the person.
- **Where:** ytj.fi (start-up notification, guided electronic form; e-filing is required for Oy from 2026)
- **Cost:** 300 € (guided electronic Oy, from 1 Jan 2026; toiminimi 75 €) — PRH decree 1216/2025 via secondary source
- **Time:** Typically 1–3 weeks for registration

## 3. Y-tunnus, VAT register, prepayment register, beneficial owners

- **What:** All on the same YTJ start-up notification. Register for VAT from day one (voluntary under the 20 000 € threshold, but Malvoya's fee revenue will pass it, and registering lets you deduct VAT on costs). Join the prepayment register (ennakkoperintärekisteri) so business customers need not withhold tax. File the Oy's beneficial owners.
- **Why:** Needed for invoices, Stripe, the bank and every legal text placeholder.
- **Where:** ytj.fi · vero.fi
- **Cost:** Included
- **Time:** With registration

## 4. Business bank account

- **What:** Open an account in the Oy's name (KYC: articles, trade register extract, ID). Pay the share capital in if you set one.
- **Why:** Stripe payouts, VAT payments and bookkeeping must be separate from personal money.
- **Where:** Any Finnish bank or business account provider
- **Cost:** About 5–15 €/month (assumption)
- **Time:** 1–2 weeks

## 5. Accountant and bookkeeping

- **What:** An Oy keeps double-entry books (Kirjanpitolaki), files monthly VAT returns in OmaVero, and files its financial statements with PRH. Keep financial statements and books 10 years, vouchers 6 years. Order records are kept after account deletion (the code anonymises users).
- **Why:** Legal duty; also needed to settle the VAT agent model (section 2).
- **Where:** An authorised accounting firm (Taloushallintoliitto member list)
- **Cost:** About 150–300 €/month at low volume (assumption)
- **Time:** 1 week

## 6. Domain and email

- **What:** malvoya.com is not under your control, so buy a domain you own (for example a .fi through a Traficom-accredited registrar), set up a business mailbox, SPF, DKIM and DMARC, then point SMTP_FROM, SUPPORT_EMAIL and the legal texts at it.
- **Why:** Apple and Google need an organisation website; receipts and support need a real address.
- **Where:** Traficom registrar list · your email provider
- **Cost:** About 10–30 €/year domain, 5–8 €/user/month email (assumption)
- **Time:** 1 day

## 7. Insurance

- **What:** Business liability (toiminnan vastuuvakuutus) and goods in transit. Couriers: if employed, statutory accident and occupational disease insurance (työtapaturma- ja ammattitautivakuutus), TyEL pension and unemployment insurance are compulsory. If freelance, require their own accident insurance and liability cover in the courier agreement, and check it at onboarding. Cyber insurance is optional.
- **Why:** Bike or moped accidents and damaged goods are the most likely claims.
- **Where:** Finnish insurers (quotes)
- **Cost:** About 400–800 €/year liability (assumption); employee accident insurance is a % of payroll
- **Time:** 1–2 weeks

## 8. Stripe live account and Connect platform

- **What:** Activate Stripe in the Oy's name, accept the Stripe Services Agreement and the Connect Platform Agreement, complete the platform profile (marketplace, separate charges and transfers, Express accounts), branding for onboarding, the live webhook secret and fraud rules. Malvoya pays card fees (standard EEA cards 1.5 % + 0,25 €) and, with platform-set pricing, 2 € per active connected account per month and 0.25 % + 0,10 € per payout.
- **Why:** No real payments or payouts without it.
- **Where:** dashboard.stripe.com
- **Cost:** No fixed fee; per-transaction fees as stated
- **Time:** 1–7 days verification

## 9. Legal texts filled and reviewed

- **What:** Fill every placeholder in legal/ (company legal name, Y-tunnus ×5, address, phone, publication dates, mediator, notice period, verification method, email provider), then a Finnish lawyer reviews customer terms, seller terms, courier agreement and privacy policy.
- **Why:** Consumer, P2B, DSA and GDPR duties all point to these documents.
- **Where:** legal/*.md → published at /legal/*
- **Cost:** About 1 500–3 000 € one-off review (assumption)
- **Time:** 2–4 weeks

## 10. GDPR

- **What:** Records of processing (Art. 30); data processing agreements with processors: Render (hosting, Frankfurt), Cloudinary (media), Google Firebase (push, phone sign-in), the email provider, Twilio if SMS is used; Stripe acts partly as an independent controller. Transfer basis for US providers (EU–US Data Privacy Framework or SCCs). A DPIA is advisable for courier location tracking and algorithmic job offers. Privacy policy placeholders to fill.
- **Why:** Fines and Play Store data-safety accuracy.
- **Where:** tietosuoja.fi (Data Protection Ombudsman guidance)
- **Cost:** Free (lawyer time)
- **Time:** 1–2 weeks

## 11. Courier model under the Platform Work Directive

- **What:** Directive (EU) 2024/2831 must be in national law by 2 Dec 2026. Finland's draft platform work act (consultation from 8–9 Jul 2026, planned in force 2.12.2026) adds a presumption of employment when facts indicate direction and control, plus rules on algorithmic management transparency, human review, health and safety and data protection. The Supreme Administrative Court held Wolt couriers to be employees in May 2025. Choose: employ part-time hourly couriers (simplest and safest), or keep freelancers genuinely free. If you employ: employer register (when a regular employer: ≥2 permanent or ≥6 temporary employees at once; otherwise just report pay to the Incomes Register), TyEL, accident insurance.
- **Why:** Misclassification is the largest legal risk for a delivery platform in 2026.
- **Where:** tem.fi / valtioneuvosto.fi (bill status) · vero.fi (employer register) · tulorekisteri.fi
- **Cost:** Employer side costs on top of wages (assumption about 20–25 %)
- **Time:** Decide before Phase 1

## 12. Consumer law

- **What:** Distance selling (Kuluttajansuojalaki ch. 6): pre-contract information, 14-day withdrawal from delivery for goods sold by business sellers, refund of the standard delivery fee, refund within 14 days. Total price including all fees shown up front (ch. 2 §8; the code's quote does this). 30-day lowest price for 'was' prices (implemented). Tell buyers whether the seller is a business or a private person, because consumer rights do not apply against private sellers (implemented as sellerType). Decide whether private sellers on Malvoya offer returns anyway.
- **Why:** KKV (Finnish Competition and Consumer Authority) enforces these.
- **Where:** kkv.fi
- **Cost:** Free
- **Time:** With the legal review

## 13. EU Digital Services Act

- **What:** For all hosting services: notice and action (Art. 16) and statements of reasons (Art. 17) — built. Online-platform and marketplace duties (Art. 20 complaints, Art. 26 ad labels, Art. 27 recommender transparency, Art. 30 trader traceability, Art. 31 trader info by design, Art. 32 informing buyers of illegal products) do not apply to micro and small enterprises (Art. 19 and 29), but most are already built and should be kept. Points of contact (Art. 11–12) and content rules in the terms (Art. 14) apply to everyone. Finland's Digital Services Coordinator is Traficom.
- **Why:** Required now; the full set applies once Malvoya grows past small-enterprise size.
- **Where:** traficom.fi · digital-strategy.ec.europa.eu
- **Cost:** Free
- **Time:** With the legal review

## 14. P2B Regulation (EU) 2019/1150

- **What:** Applies to shops that are businesses, whatever Malvoya's size. Seller terms in plain language; 15 days' notice of any change (Art. 3); reasons before restricting or suspending a shop and 30 days before terminating (Art. 4); main ranking parameters, including any paid influence (Art. 5); data access description (Art. 9). The internal complaint system (Art. 11) and mediators (Art. 12) are not required for small enterprises, but the seller terms already promise complaints and name a [MEDIATOR] placeholder.
- **Why:** Every commission or ranking change, and sponsored Drops, go through these rules.
- **Where:** eur-lex.europa.eu (32019R1150)
- **Cost:** Free
- **Time:** With the legal review

## 15. DAC7 seller reporting

- **What:** As a platform operator resident in Finland, report sellers' identity, sales and consideration per quarter to Vero via Ilmoitin.fi by 31 January for the previous year; also report when there is nothing to report. Excluded: sellers of goods with fewer than 30 sales and at most 2 000 € in the year. Built: tax-info screen, encrypted TIN, admin DAC7 export. Needs DATA_ENCRYPTION_KEY on Render.
- **Why:** Penalties for missing reports.
- **Where:** vero.fi DAC7 · ilmoitin.fi
- **Cost:** Free
- **Time:** First report January of the year after launch

## 16. YEL pension insurance

- **What:** Required for an entrepreneur aged 18–69 whose estimated work income is at least 9 423,09 €/year (2026). For an Oy, it applies to a managing director or board member owning more than 30 % alone (or more than 50 % with family). Set the YEL income with a pension company within 6 months of starting.
- **Why:** Statutory; it also sets sickness and parental benefits.
- **Where:** Any earnings-related pension company · etk.fi
- **Cost:** About 24 % of the YEL income (assumption, check the 2026 rate; new entrepreneurs get a discount)
- **Time:** Within 6 months

## 17. D-U-N-S number

- **What:** Free number from Dun & Bradstreet that Google and Apple use to verify a company. Names and addresses must match the trade register exactly.
- **Why:** Needed for both organisation developer accounts.
- **Where:** dnb.com (D-U-N-S request) · developer.apple.com/support/D-U-N-S
- **Cost:** Free
- **Time:** Up to 30 days

## 18. Google Play developer account

- **What:** A personal account works today but needs a closed test with 12 testers for 14 days for each app and shows your own name. An organisation account needs the Oy and a D-U-N-S number, skips the tester rule, and the apps can be transferred to it later.
- **Why:** Shops and couriers should see Malvoya Oy, not a private person, as the developer.
- **Where:** play.google.com/console · docs/play-store-release-checklist.md
- **Cost:** 25 USD one-time
- **Time:** A few days after D-U-N-S

## 19. Apple Developer Program

- **What:** Organisation enrolment needs a legal entity (no trade names), a D-U-N-S number, a website on the company domain and a phone check. Needed for the iPhone apps.
- **Why:** Without an iPhone app a large share of Finnish customers cannot order.
- **Where:** developer.apple.com/programs/enroll
- **Cost:** 99 USD/year (local-currency price may apply)
- **Time:** 1–2 weeks after D-U-N-S

## 20. Trademark filing

- **What:** File "Malvoya" (word mark, then logo) in classes 35 (online marketplace and retail services), 9 (apps), 39 (delivery) and 42 (software platform). Start with PRH for Finland, or EUIPO for the whole EU.
- **Why:** Protects the brand before marketing spend.
- **Where:** prh.fi (online) · euipo.europa.eu
- **Cost:** PRH 250 € + 100 € per extra class (from 1 Jan 2026); EUIPO 850 € first class, +50 € second, +150 € each further
- **Time:** PRH about 1 month processing, then a 2-month opposition period

## 21. Accessibility (European Accessibility Act)

- **What:** E-commerce services must meet accessibility requirements since 28 June 2025. Micro-enterprises providing services (under 10 staff and at most 2 M€ turnover) are exempt, but plan for it before hiring.
- **Why:** Applies as Malvoya grows; customers expect it anyway.
- **Where:** Traficom (market surveillance)
- **Cost:** Design time
- **Time:** Before Phase 2

## Sources (read 16 Oct 2026)

- PRH fees from 1 Jan 2026 (decree 1216/2025), via https://talousarvo.fi/prh-tiedottaa-muutokset-kasittelymaksuissa-1-1-2026-alkaen/
- PRH trademark fees: https://prh.fi/en/price-lists/trademark_fees/fees_for_trademark_applications.html
- VAT rates: https://vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/rates-of-vat/ ; VAT threshold 20 000 €: https://www.vero.fi/yritykset-ja-yhteisot/verot-ja-maksut/arvonlisaverotus/vahainen-liiketoiminta-on-arvonlisaverotonta/
- DAC7: https://www.vero.fi/en/businesses-and-corporations/taxes-and-charges/annual-information-returns/dac7/
- YEL 2026: https://www.etk.fi/wp-content/uploads/2026/01/yrittajan-elaketurvan-abc-2026.pdf
- Platform work act draft: https://www.edilex.fi/uutiset/102362 ; KHO 2025: https://www.yrittajat.fi/uutiset/kho-wolt-lahetit-ovat-tyontekijoita-rajanveto-jatkossakin-aina-tapauskohtaisesti/
- Stripe: https://stripe.com/fi/pricing , https://stripe.com/fi/connect/pricing
- Google Play: https://support.google.com/googleplay/android-developer/answer/14151465 ; Apple D-U-N-S: https://developer.apple.com/support/D-U-N-S/
- EUIPO fees (third-party guide): https://tmarkmetric.com/insights/eu-trademark-cost
