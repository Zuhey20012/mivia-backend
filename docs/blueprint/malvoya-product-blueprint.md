# Malvoya product blueprint: where we are, where we must reach, and how

Written 22 Oct 2026. It brings together everything in `docs/` (operating plan, compliance, design system audit, ADR-001, Home and Drops redesign, categories v2) into one picture. Market facts come from the dated sources in those documents. Everything else is labelled as judgement.

---

## 1. The market we enter (Finland, autumn 2026)

| Player | What they own | Their weakness Malvoya can use |
|---|---|---|
| **Wolt** (DoorDash) | Delivery habit in Finland, courier fleet, Wolt+ subscription, retail beyond food | Fashion and beauty are side categories, with no styling, shade or fit help; generic store pages |
| **Uber Eats** (Helsinki since 6 May 2026, 11 areas by Aug) | Money, global app, retail partnerships, robot delivery trials | New in Finland; food-first; no local fashion curation |
| **Zalando** | Huge catalogue, free returns, fit data, brand deals | Not local; delivery takes days; no "see it today in a shop near you" |
| **Vinted / Tori** | Second-hand habit, very low prices | Slow (post), no curation by shops, trust issues |
| **Sephora (online), Lyko, Kicks** | Beauty depth: shades, ingredients, loyalty | No same-day local delivery from independent shops |
| **Foodora** | Left Finland 27 Feb 2026 | Couriers and some shops are looking for a new platform |

**Malvoya's position (judgement):** *"Your city's fashion and beauty shops, on video, delivered today or ready to pick up."* Don't compete on speed with Wolt, range with Zalando, or price with Vinted. Win on **local + today + video + trust**.

---

## 2. Where we are: an honest scorecard (1 = idea, 5 = market leader)

| Capability | Malvoya | Wolt | Zalando | Gap to close before launch |
|---|---|---|---|---|
| Order, pay, track, return, payouts | 4 | 5 | 5 | real-phone testing; Google Pay / Apple Pay in the payment sheet (verify it is enabled) |
| Catalogue and categories | 2.5 → 4 (in progress) | 4 | 5 | categories v2, shade/size data, search typo tolerance |
| Discovery and inspiration (video, rails) | 3.5 | 3 | 4 | the Drops tab dot, seasonal collections, better search |
| Personalisation | 1 | 4 | 5 | saved sizes and shades (no consent needed), then consented recommendations |
| Trust (reviews, returns, safety) | 3.5 | 4 | 5 | photo reviews, clear returns hub, safety block (in progress) |
| Courier experience | 4 | 5 | n/a | real shifts, fair pay settings, insurance |
| Merchant tools | 3.5 | 5 | 4 | a web dashboard for big catalogues, a bulk editor, analytics for shops |
| Reliability and scale | 2 | 5 | 5 | CI, monitoring, multi-instance (in progress) |
| iPhone app | 1 | 5 | 5 | Apple account, Codemagic, Sign in with Apple |
| Web shop / SEO | 1 (share pages only) | 4 | 5 | **a web storefront**: Zalando and Wolt get much of their traffic from Google |
| Business operations | 1 | 5 | 5 | company, Stripe live, prices, insurance, lawyer |
| Supply (shops, couriers) | 0 | 5 | 5 | the closed beta in one district |

**Summary:** the product is ahead of a typical startup at launch, the business is at zero, and the iPhone app and web shop are the two biggest product gaps that competitors take for granted.

---

## 3. What really excites consumers (and what we must never do)

What makes people open an app again. These are behavioural drivers, with the Malvoya feature for each:

| Driver | Why it works | Malvoya feature |
|---|---|---|
| **Instant gratification** | "I can have it tonight" beats "it's 20 % cheaper online" for many fashion and beauty buys | same-day delivery, reserve & collect with a pickup code, a live ETA countdown |
| **Newness and discovery** | people return for what's new | Drops videos, "New in near you", the Drops tab dot, follow shops |
| **Confidence to buy** | fit and shade uncertainty is the top reason to abandon and return | size charts in cm, "find my size", shade swatches, photo reviews, honest returns info |
| **Effortless repeat** | the second order decides retention | reorder, saved sizes and shades, saved addresses, Google/Apple Pay one-tap |
| **Small delights** | the micro-moments people tell friends about | the paid moment, the courier marker gliding home, haptics, shop-written thank-you notes |
| **Belonging and local pride** | supporting the shop on your street feels good | shop stories, Made in Finland (verified), the shop owner on video |
| **Fair rewards** | first-order and invite rewards drive trial | promo codes and referrals (built, off by default), loyalty later |
| **Feeling respected** | no tricks means trust means retention | the honest prices shown up front, no fake urgency |

**Never do (illegal or trust-killing):**
- fake urgency ("only 2 left!" when not true) or fake scarcity timers (Unfair Commercial Practices Directive);
- fake "X people are viewing this";
- pre-ticked add-ons;
- hidden fees;
- confirm-shaming ("No, I don't like saving money");
- dark patterns in consent (DSA Art. 25, GDPR);
- generic green claims (Directive 2024/825);
- profiling ads to minors (DSA Art. 28).

Real scarcity, like a one-off second-hand item or a shop's real stock count, may be shown, truthfully.

---

## 4. UX and UI standards the apps must meet

| Area | Standard | Where we are |
|---|---|---|
| Speed | Home useful < 1.5 s cached; product page < 1 s; tap response < 100 ms | not measured yet: add performance tracing |
| Smoothness | 60 fps scroll on a Galaxy A-series; skeletons that match the final layout | partly; to verify on device |
| One-handed use | main actions in the bottom third; 48 dp targets | mostly done |
| Clarity | one primary action per screen; plain bilingual copy; errors say what to do | done in most flows |
| Accessibility | WCAG 2.1 AA, text scale 1.3, screen reader labels, reduce motion | partly; audit planned |
| Consistency | one design system (`malvoya_ui`), tokens only | in progress (audit score 48/100) |
| Honesty | real data only, empty states instead of filler | done |
| Feedback | every action answers in < 100 ms (haptic or visual), success moments | done in key flows |

The design direction stays **Birch Market**:
- warm birch background, sunshine accent, pastel category tiles, Bricolage display type;
- one brand colour per app: Malva for customers, Moss for stores, Lingon for couriers.

---

## 5. System architecture (today and the path to large scale)

```
      Customer app     Store app      Courier app      Admin (web)     [Web shop: to build]
           │               │               │                │                 │
           └───────────────┴──── HTTPS / WebSocket ─────────┴─────────────────┘
                                       │
                         Render Frankfurt: Node API (modular monolith)
           modules: auth · stores · products · categories · orders · dispatch · couriers ·
                    payouts · returns · drops · legal/agreements · safety · admin · home
                                       │
          ┌──────────────┬─────────────┼──────────────┬───────────────┬──────────────┐
      Postgres       Redis (opt.)   Worker (opt.)   Stripe          Firebase       Cloudinary
      (Render;       sockets, rate  emails, push,   payments,       FCM push,      images, video
       PITR backups) limits, cache  imports,        Connect         phone sign-in, (HLS), CDN
                                    reports         payouts         Crashlytics
          Other: SMTP email · PRH open data (business check) · OpenStreetMap tiles/geocoding
```

**Scale stages** (detail in `docs/scaling/` when the scale work lands):
- **Launch:** 1 instance + Postgres.
- **About 10k orders/day:** 2–4 instances + Redis + worker.
- **About 100k/day:** autoscaling, read replicas, a CDN for `/home` and public GETs, a dedicated search engine.
- **1M+/day:** split the hot modules (dispatch, search) into their own services, a multi-region read path, and a dedicated data warehouse for analytics.

Every stage is switched on by settings, not rewrites.

---

## 6. Firebase console: what has to be set up (owner tasks, step by step)

Firebase does three jobs: **push notifications** (FCM), **phone sign-in** and **crash reports** (Crashlytics, to add).

1. **Project:** one Firebase project for production, e.g. "malvoya-prod". A second, "malvoya-dev", for testing is recommended.
2. **Add 3 Android apps:**
   - The package names are `com.malvoya.customer`, `com.malvoya.vendor` and `com.malvoya.courier`.
   - Add the **SHA-1 and SHA-256** of the upload key *and* of Play App Signing (from Play Console → App integrity).
   - Download each `google-services.json` into the app's `android/app/`. They are not secret, but don't publish them on purpose.
3. **Later, add 3 iOS apps:**
   - First fix the bundle IDs (they are still `com.example.miviaApp`; see `docs/app-store-release-checklist.md`).
   - Upload an **APNs key** (Apple Developer → Keys) so iPhones get push.
4. **Cloud Messaging:** enabled by default. Nothing else to do.
5. **Authentication → Phone:**
   - Enable it.
   - Set **SMS region policy** to allow Finland (and EU) only, which stops SMS fraud costs.
   - Enable **App Check** (Play Integrity) so only the real apps can request codes.
   - Set a **budget alert** in Google Cloud billing (e.g. 20 €/month).
6. **Service account for the server:**
   - Project settings → Service accounts → Generate new private key.
   - Paste the whole JSON into Render as `FIREBASE_SERVICE_ACCOUNT`.
   - Never send it in chat, never commit it, and delete the downloaded file afterwards.
7. **Crashlytics:** enable it in the console; the apps need the Crashlytics package (part of ADR-001 step 6).
8. **Analytics:** only with consent (Consent Mode, defaulting to denied). Malvoya's privacy policy must list it before it is turned on.

---

## 7. The laws, in one list (details in `docs/compliance/` and `docs/business/paperwork-checklist.md`)

- **Consumer protection:** distance selling, 14-day withdrawal, prices with all fees, unit prices, the hygiene-seal exception.
- **Digital Services Act:** notice and action, statements of reasons, trader traceability, no dark patterns, minors' protection.
- **P2B Regulation:** shop terms, 15-day change notice, ranking transparency.
- **GDPR:** records of processing, processor agreements, consent for analytics, data export and deletion (built).
- **DAC7:** seller reporting to Vero (built).
- **General Product Safety Regulation:** listing information, recalls (in progress).
- **Textile and cosmetics labelling** (in progress).
- **Green claims ban** (eco flag being removed).
- **Platform Work Directive / Finnish draft law** (from 2 Dec 2026): presumption of employment, algorithm transparency. The courier model decision is the owner's.
- **Accessibility** (European Accessibility Act; Malvoya is exempt as a micro-enterprise, but build to it anyway).

---

## 8. What to simulate before real money moves

| Simulation | Question it answers | Status |
|---|---|---|
| Unit economics calculator | does an order make money at these prices? | built (operating plan) |
| Load tests | how many shoppers per server, where it breaks | in progress (scale work) |
| **Dispatch simulation** | with N couriers on shift and M orders/hour in one district, how long do customers wait and what does a courier earn per hour? | **to build**: a small script on real map distances, for deciding shift sizes and the courier pay settings |
| End-to-end test suite | does every flow work after each change? | built (672 checks); app tests to add |
| Usability tests (real people) | can shoppers, shops and couriers do their tasks without help? | to run on 1.8.0 |
| Closed beta (20 real orders) | does it all work with real money, real shops, real streets? | after the company exists |

---

## 9. The road: from here to a product that can stand next to Wolt and Zalando

**Phase A: finish the product core (now, about 2–3 weeks of agent work).**
1. Categories v2 with shades, sizes, ingredients and collections; the eco claim removed; the product-safety block (server in progress).
2. The shared design system and core library (in progress).
3. New Home (Drops moved to their own tab, services row, collections), category screens, store templates. Build 1.8.0.
4. ADR-001 baseline: CI, tests, Crashlytics.

**Phase B: be launch-ready (owner + agents, about 4–6 weeks).**
- **Owner:** company, bank, Stripe live, prices, insurance, lawyer review, Firebase and SMTP set up, Google Play account.
- **Agents:** Google Pay in checkout, photo reviews, saved sizes and shades, the dispatch simulation, the scale stage-1 settings, a performance pass on a real phone.
- **Together:** usability tests with 5 + 3 + 3 people, then fixes.

**Phase C: closed beta in one district (8–12 weeks).** 15+ shops, 4–6 couriers, the waiting list in waves. Exit criteria are in the operating plan (15+ orders a day, ≥ 90 % on time, ≥ 25 % repeat).

**Phase D: grow (months 4–12).**
- the iPhone app;
- a **web storefront** (SEO plus share links that open a real shop page);
- a merchant web dashboard;
- consented personalisation;
- loyalty;
- Helsinki, Espoo and Vantaa.

**What decides success, in order:** (1) enough great shops in one area, (2) delivery that actually arrives today, (3) fit and shade confidence, (4) trust, (5) delight. The code is ready for 1–5; supply and operations decide whether they happen.
