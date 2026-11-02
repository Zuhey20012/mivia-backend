# Litigation-risk shield (Finland / EU)

Status: 2.16.0, 30 October 2026. Written by the engineering side for the owner and the lawyer. **This is not legal advice**; every "for the lawyer" line is an open question.

The owner listed six well-known US litigation risks. Malvoya is a Finnish service for shoppers, sellers and couriers in Finland, so most of the US rules do not apply as such. Each section says whether it applies, what the Finnish/EU equivalent is, what Malvoya does now (with the code), and what the owner still has to do.

| # | Risk raised | Applies to Malvoya? | Finnish / EU equivalent |
|---|---|---|---|
| 1 | US COPPA (children's data, up to $53,088 per violation) | No (US law, US-directed services) | GDPR Art. 8 + Data Protection Act 1050/2018 §5 (13 years); DSA Art. 28; Malvoya's own 18+ rule |
| 2 | Google Fonts (IP address sent to Google) | Yes, in substance | GDPR Art. 6 and 44 ff.; German case law (LG München I, 20 Jan 2022, 3 O 17493/20) |
| 3 | Session replay / analytics scripts | Yes, in substance | ePrivacy Art. 5(3) = Act on Electronic Communications Services 917/2014 §205 (consent); GDPR |
| 4 | Email unsubscribe (CAN-SPAM) | Yes | 917/2014 §200 (direct marketing), ePrivacy Art. 13; RFC 8058 one-click for bulk senders |
| 5 | Auto-renewal / subscription traps | Not today (no membership exists) | Consumer Protection Act (KSL) ch. 2, 3 and 6; Consumer Ombudsman (KKV) practice |
| 6 | DMCA (up to $150,000 per work) | No (US law); the EU notice-and-action rules apply instead | DSA Art. 16, 17, 20, 23; Copyright Act 404/1961; 917/2014 §§189–193 (check in force) |

---

## 1. Children's data (US COPPA, $53,088 per violation)

**Applies?** No. COPPA (15 U.S.C. §§6501–6506, 16 CFR Part 312) covers operators of services directed to children under 13 in the US or with actual knowledge of collecting US children's data. The $53,088 figure is the FTC's inflation-adjusted civil penalty per violation (16 CFR §1.98) that the owner quoted; it was not re-checked in this session.

**Finnish / EU equivalent.**
- GDPR (EU) 2016/679 Art. 8: consent of a child to an information society service needs a parent's consent below the national age. In Finland that age is **13**: Data Protection Act (tietosuojalaki) 1050/2018 §5 ("lapsen henkilötietojen käsittely on lainmukaista, jos lapsi on vähintään 13-vuotias"; read from Finlex open data on 30 Oct 2026). Malvoya does not rely on consent for its core processing (contract), so Art. 8 is narrow here, but a contract with a minor is also limited by the Guardianship Services Act (holhoustoimilaki) — for the lawyer.
- DSA (EU) 2022/2065 Art. 28: online platforms accessible to minors must ensure a high level of privacy, safety and security, and must not show profiling-based ads to minors.

**What Malvoya does (2.16).**
- The Terms of Service (§3), Seller Terms (§2, new) and Courier Agreement (§3) require users to be 18+.
- Every registration screen has a required **"I am 18 or older / Olen vähintään 18-vuotias"** box; `POST /auth/register` answers 400 without `ageConfirmed: true` (`auth.schema.ts`) and stores `User.ageConfirmedAt`.
- Google, phone, Apple and email-code accounts confirm it in the agreement sheet: `GET /me/agreements → ageConfirmationRequired`, `POST /me/agreements/accept {ageConfirmed: true}`, and `requireAgreement()` answers 428 `AGREEMENT_REQUIRED` with `ageConfirmationRequired: true` before ordering, selling (accepting orders, publishing, importing, going live) and going online as a courier.
- Guests can browse without an account; no data about them is stored beyond technical logs.
- `User.isMinor` and `lib/minors.ts#mayPersonalise` stay as the DSA Art. 28 guard (no profiling of known or likely minors).

**Owner / lawyer.**
- A self-declared tick box is not age verification. Decide whether that is proportionate for a fashion and beauty marketplace (no age-restricted goods are sold). If alcohol-free fragrance, piercing jewellery or other goods with age limits are ever added, a real age check is needed.
- Confirm the Finnish wording "Olen vähintään 18-vuotias" and whether accounts created before 2.16 may be asked once (they are: their `ageConfirmedAt` is empty).

## 2. Google Fonts (remote fonts)

**Applies?** In substance, yes. Loading fonts from `fonts.googleapis.com` / `fonts.gstatic.com` sends each visitor's IP address to Google in the US. LG München I (20 Jan 2022, 3 O 17493/20) awarded €100 damages for this under GDPR; Finnish courts have not ruled, but the GDPR is the same.

**What Malvoya does.**
- All fonts are bundled (apps: `core/font_licenses.dart`; the brand rule "never load fonts from the network" in CLAUDE.md; web and admin use local fonts).
- New in 2.16: the CI job **privacy-guard** (`.github/workflows/ci.yml`) fails the build if `fonts.googleapis`, `fonts.gstatic` or any known analytics or session-replay script appears in `web/src`, `malvoya_admin/src`, `backend/src`, the three apps' `lib/` or the shared packages.

**Owner.** Keep it that way. Any third-party embed (maps, video, chat widgets) needs the same review.

## 3. Session replay and analytics scripts

**Applies?** In substance, yes. Session-replay tools (Hotjar, FullStory, Microsoft Clarity, LogRocket, Smartlook) and analytics (Google Analytics/gtag, PostHog, Mixpanel) store or read data on the user's device and record behaviour. Finland: **917/2014 §205** requires the user's consent for storing or using data on the device unless strictly necessary for the service the user asked for (read from Finlex open data on 30 Oct 2026; implements ePrivacy Directive 2002/58/EC Art. 5(3)). Consent must be prior, informed and active (CJEU C-673/17 *Planet49*). Traficom supervises §205; the Data Protection Ombudsman (tietosuoja.fi) supervises the personal data.

**What Malvoya does.** No trackers, no analytics SDKs, no ads (Privacy → "No ads, no analytics trackers"; the website states it uses no cookies). Crash reports (Crashlytics, if set up) carry only the numeric user id, app version and role. The privacy-guard CI job blocks the listed scripts.

**Owner.** Before adding any analytics: a consent design (no pre-ticked boxes, reject as easy as accept), a privacy-policy update and a DPIA if replay is used. The CI list must be extended for any new vendor.

## 4. Email unsubscribe

**Applies?** Yes. **917/2014 §200**: electronic direct marketing to a natural person needs prior consent; an existing customer may get marketing for the seller's own similar products, but must be able to refuse it "ilman erillistä maksua ja helposti" at collection and **in every message** (read 30 Oct 2026). Gmail and Yahoo require one-click unsubscribe (RFC 8058) for bulk senders.

**What Malvoya does (2.16).**
- Every email the backend sends is classified (`services/notificationDeliveryService.ts`, the table at the top):
  - transactional (always sent, each with a one-line footer saying why): sign-in/reset codes and security notices (`account`), order confirmations, status, cancellations and withdrawal acknowledgements (`order`), agreement copies and legal-text changes (`legal`), recalls (`recall`), approvals, DAC7 reminders, statements of reasons and payout matters (`seller`), support acknowledgements (`support`), report outcomes (`report`); team-only mail (`internal`) has no footer;
  - optional: the launch alert ("Malvoya is open near you", now also by email); any future referral, promo or newsletter email must use `sendOptionalEmail`.
- Optional emails carry an unsubscribe link in the footer and the `List-Unsubscribe: <https://…/email/unsubscribe?t=…>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers. The token is an HMAC of the user id that never expires (`lib/unsubscribe.ts`). `POST /email/unsubscribe?t=` is the one-click; `GET` shows a bilingual page with one button (mail scanners open links, so GET changes nothing).
- `User.emailMarketingOptOutAt` is respected by `sendOptionalEmail`; Profile → Privacy → **Email preferences** switches optional emails on/off (`PATCH /me {emailMarketing}`) and cancels the launch alert (push + email).

**Owner / lawyer.**
- The only optional email today is the launch alert, which the user explicitly asked for. **Any real marketing (promos, newsletters, referral campaigns) needs prior opt-in consent** under §200(1), or must stay within the existing-customer exception of §200(3). The current switch is "on" by default because of that; flip the default to off before any marketing email is added.
- `SMTP_FROM` should be a domain with SPF/DKIM/DMARC once Malvoya has its own domain.

## 5. Auto-renewal and memberships

**Applies?** Not today: Malvoya sells no subscription or membership. If one is introduced, Finnish consumer law applies in full.

**Finnish / EU rules to follow** (for the lawyer to confirm before launch):
- **Price, renewal period and cancellation terms right next to the pay button.** KSL ch. 6 §9 (pre-contract information: total price, for an open-ended or automatically renewing contract the price per billing period, the duration and the conditions for ending it) and the "order with obligation to pay" button rule (CRD Art. 8(2), implemented in KSL ch. 6). A free or discounted trial that turns into a paid membership must say so, with the date and the price, before the customer commits.
- **A reminder before each renewal**, by email or push, with the date, the price and a direct cancellation link. Not a general statutory rule in Finland today; the Consumer Ombudsman treats hidden renewals as unfair practice (KSL ch. 2), and the EU's planned Digital Fairness Act is expected to address it. Treat it as required.
- **Cancellation as easy as signing up**: in the app, in the same number of steps, without a phone call. The Consumer Ombudsman's position is that cancelling must be as easy as making the contract and possible at least in the channels where it can be made (KKV / Consumer Ombudsman; see the Ruutu+ and Elixia cases reported by the press; official KKV text to be read by the lawyer).
- **Continuing contracts (toistaiseksi voimassa olevat sopimukset):** no unreasonably long notice periods or fixed terms (KSL ch. 3 §1 unfair terms; the Consumer Ombudsman has taken a three-month notice period to the Market Court), no unilateral price rises without a valid clause and advance notice, and the right of withdrawal for distance contracts (KSL ch. 6) including, since 19 June 2026, the withdrawal function (KSL ch. 6 §14 a).
- Payments only through Stripe (no card fields in the apps).

**Owner.** Do not ship a membership until the lawyer has signed off the screen texts, the reminder and the cancellation flow.

## 6. Copyright and trademark (US DMCA, up to $150,000 per work)

**Applies?** The DMCA (17 U.S.C. §512 safe harbour; statutory damages up to $150,000 per work for wilful infringement under §504(c)(2)) is US law and does not apply to Malvoya. In the EU the host's liability and the notice procedure come from the **DSA** (Art. 6 liability exemption; Art. 16 notice and action; Art. 17 statement of reasons; Art. 20 internal complaints; Art. 21 out-of-court settlement; Art. 23 measures against misuse and repeat infringers), plus the Copyright Act 404/1961 and the Trademarks Act 544/2019. 917/2014 §§189–193 contain a Finnish copyright notice and counter-notice ("vastine") procedure; the consolidated text read on 30 Oct 2026 was the version as amended by 1211/2022, and Finlex also lists a 2024 amendment (661/2024) — **for the lawyer: confirm whether §§184–193 are still in force after the national DSA implementation.** DSM Directive Art. 17 (Copyright Act ch. 6a) concerns large content-sharing services; for the lawyer to confirm it does not apply to Malvoya.

**What Malvoya does (2.16).**
- Reports of products, drops and drop comments take the reasons **copyright** and **trademark** (`COPYRIGHT`/`TRADEMARK` for drops and comments). For them the API requires the DSA Art. 16(2) fields: name, email, the work or mark, where it is, optional "acting for", and the good-faith statement (`lib/ipNotice.ts`; 400 `IP_NOTICE_REQUIRED` without them). The customer app asks for them in a form (`widgets/ip_notice_form.dart`).
- Admins see the notice in the existing queues (Product reports, Moderation → drop reports and reported comments). Removal uses the existing statement-of-reasons flow (email + push to the store with how to object).
- `legal/ip_notice.md`, served at `/legal/ip-notice` (alias `/legal/copyright`) and linked from every legal page and the website's Legal page, explains how rights holders report, the counter-notice route for sellers and the repeat-infringer policy, and says the DMCA does not apply.
- Seller Terms §3 (new clause): sellers must own or license their photos and texts; the import "rights confirmation" is binding.
- Account deletion keeps the notice (it must be processed) but removes the notifier's name and email from it.

**Owner / lawyer.** Confirm the repeat-infringer thresholds (`[3]` upheld notices in `[12]` months), whether the notifier's identity is shared with the seller, and the Finnish texts.

---

## The withdrawal function (since 19 June 2026)

Not one of the six risks, but the newest consumer rule: **KSL ch. 6 §14 a** (Act 31/2026 amending the Consumer Protection Act, published 21 Jan 2026, chapters 1, 6 and 6a in force **19 June 2026**; implements Directive (EU) 2023/2673, which inserted **Art. 11a** into the Consumer Rights Directive 2011/83/EU). Read from the Finlex PDF on 30 Oct 2026. It requires, for distance contracts concluded through an online interface: a withdrawal function that lets the consumer give or confirm their name, the contract and the durable medium for the acknowledgement; easily available and prominently displayed for the whole withdrawal period, labelled clearly and legibly; a confirmation step; and an acknowledgement on a durable medium without undue delay with the content and the date and time of the withdrawal. The Finnish act does not prescribe the label text; the directive's English text uses "withdraw from contract here" and "confirm withdrawal" (as summarised by the secondary sources below; EUR-Lex itself could not be read from this environment).

Malvoya 2.16: "Withdraw from contract here / Peru sopimus tästä" on each delivered order from a business seller within the period and in Profile → Returns; a short form (items, optional reason) and "Confirm withdrawal / Vahvista peruminen"; `POST /returns {withdrawal: true}` marks the return, and an acknowledgement email (SMS for phone-only accounts) with the date and time, order, items and next steps is sent at once and recorded (`Return.withdrawalAckSentAt/Channel`). Private sellers' orders say plainly that the statutory right does not apply (422 `WITHDRAWAL_NOT_APPLICABLE`). The hygiene-seal exception works as before.

For the lawyer: the Finnish labels; withdrawal **before delivery** (the right exists from the conclusion of the contract, but the function is offered only after delivery — before that the customer can cancel only until the shop accepts); accounts with neither a deliverable email nor a phone (the app's confirmation screen is then the only record); Malvoya sending the acknowledgement on the seller's behalf (Seller Terms §5 now says so).

## Sources

Read in this session (30 October 2026):
- Finlex, Act 31/2026 amending the Consumer Protection Act (KSL ch. 6 §14 a; entry into force) — https://www.finlex.fi/api/media/statute/903794/mainPdf/main.pdf
- Finlex open data, Data Protection Act 1050/2018 §5 — https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute/2018/1050/fin@
- Finlex open data, Act on Electronic Communications Services 917/2014 §§189–193, 200, 205 (consolidated version fin@20221211) — https://opendata.finlex.fi/finlex/avoindata/v1/akn/fi/act/statute-consolidated/2014/917/fin@20221211
- Secondary summaries of CRD Art. 11a (EUR-Lex was not reachable from this environment): RDJ, "EU introduces mandatory withdrawal button" (12 Jun 2026) https://www.rdj.ie/insights/eu-introduces-mandatory-withdrawal-button-for-online-consumer-contracts ; William Fry https://www.williamfry.com/knowledge/world-consumer-rights-day-part-3-mandatory-withdrawal-button-coming-june-2026/ ; iubenda https://www.iubenda.com/en/blog/online-withdrawal-function-eu-directive-2023-2673/
- Press reports of the Consumer Ombudsman's position on cancellation (not KKV's own page): Verkkouutiset, "Kuluttaja-asiamies huolestui – palveluiden irtisanominen tehdään liian hankalaksi" https://www.verkkouutiset.fi/a/kuluttaja-asiamies-huolestui-palveluiden-irtisanominen-tehdaan-liian-hankalaksi/

Official sources cited but not fetched in this session (the lawyer should read the versions in force):
- EUR-Lex: Directive (EU) 2023/2673 — https://eur-lex.europa.eu/eli/dir/2023/2673/oj ; Directive 2011/83/EU (consolidated) — https://eur-lex.europa.eu/eli/dir/2011/83/oj ; GDPR — https://eur-lex.europa.eu/eli/reg/2016/679/oj ; DSA — https://eur-lex.europa.eu/eli/reg/2022/2065/oj ; ePrivacy Directive 2002/58/EC — https://eur-lex.europa.eu/eli/dir/2002/58/oj
- Finlex: Consumer Protection Act 38/1978 — https://www.finlex.fi/fi/lainsaadanto/1978/38 ; Copyright Act 404/1961 — https://www.finlex.fi/fi/lainsaadanto/1961/404 ; Trademarks Act 544/2019 — https://www.finlex.fi/fi/lainsaadanto/2019/544
- KKV (Competition and Consumer Authority / Consumer Ombudsman) — https://www.kkv.fi
- Traficom, cookies and §205 guidance — https://www.traficom.fi
- Data Protection Ombudsman — https://tietosuoja.fi
- RFC 8058 (one-click unsubscribe) — https://www.rfc-editor.org/rfc/rfc8058 ; RFC 2369 — https://www.rfc-editor.org/rfc/rfc2369
- US (for comparison only): COPPA 15 U.S.C. §§6501–6506, 16 CFR Part 312 and §1.98; DMCA 17 U.S.C. §512 and §504(c)
