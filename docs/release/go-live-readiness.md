# Go-live readiness: everything needed for Malvoya to work from day one

Checked 29 Oct 2026 against the live API (2.12.0, Render Frankfurt), apps 1.8.0+10, the website and the admin panel.

**Priority:** **P0** = nothing works for real customers without it · **P1** = needed before the public launch · **P2** = within the first months.
**Status:** ✅ done · 🟡 partly · ❌ not done.

## 1. Readiness at a glance

| Area | Maturity | What is missing |
|---|---|---|
| Server code (API, rules, payments, timers) | ✅ high: 817 automated checks, CI on GitHub | nothing blocking |
| Apps (Android) | 🟡 built and code-checked, **never tested on a real phone** | a phone test of 1.8.0, crash reports |
| Apps (iPhone) | 🟡 prepared, never built | your Mac build, Apple account |
| Website | ✅ live | own domain later |
| Admin panel | ✅ live | admin account on the live server |
| Payments | 🟡 Stripe **test mode** | company, Stripe live keys, webhook secret |
| Push notifications | ❌ off | Firebase service-account key on Render |
| Email (password reset, receipts) | ❌ off | SMTP on Render |
| Photos and videos | ❌ off | Cloudinary keys on Render |
| Legal | 🟡 all texts written | company details in the placeholders, lawyer review |
| Business | ❌ | company, bank, insurance, prices, first shops and couriers |

## 2. Render: the API service `malvoya-api-eu`

### 2a. Service settings (Render dashboard → malvoya-api-eu → Settings)
| Setting | Now | Set to | Priority | Why |
|---|---|---|---|---|
| Health Check Path | empty | **`/health/ready`** | P0 | Render then only switches to a new version once it can reach the database, and restarts a stuck server automatically |
| Instance type | Starter (512 MB) | **Standard** (2 GB) before the beta | P1 | Starter can run out of memory with real traffic and video processing |
| Auto-deploy | on, from `master` | keep | — | every tested release goes live automatically |
| Postgres `malvoya-db-eu` → storage autoscaling | off | **on** | P1 | the database never fills up and stops |
| Postgres backups | Render default | check point-in-time recovery is available on your plan | P1 | restore to any minute after a mistake |
| Notifications | default | add your email for failed deploys | P1 | you hear about problems first |

### 2b. Environment variables (Render → malvoya-api-eu → Environment)
Secrets: **paste them yourself, never send them in chat.**

| Variable | Priority | What it switches on | Where to get it |
|---|---|---|---|
| `STRIPE_SECRET_KEY` (live `sk_live_…`) | P0 | real payments | Stripe dashboard (after the company and Stripe live activation) |
| `STRIPE_WEBHOOK_SECRET` | **P0** | orders get confirmed as paid | Stripe → Developers → Webhooks → add endpoint `https://malvoya-api-eu.onrender.com/api/v1/payments/webhook`, copy the signing secret |
| `FIREBASE_SERVICE_ACCOUNT` | **P0** | all push notifications (new-order alarm, job offers, order updates) | Firebase → Project settings → Service accounts → Generate new private key (paste the whole JSON) |
| `FIREBASE_PROJECT_ID` = `mivia-4f159` | **P0** | checking phone and Apple sign-ins | the Firebase project ID |
| `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | **P0** | product photos, Drops videos, delivery photos, certificate files | cloudinary.com → Dashboard |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | **P0** | password reset, receipts, agreement copies, recall notices | a transactional email service on your own domain (e.g. Brevo, Postmark, Mailgun) is more reliable than Gmail |
| `SUPPORT_EMAIL` | P1 | support messages also arrive by email | your support address |
| `DATA_ENCRYPTION_KEY` | P1 | shops can save tax IDs (DAC7) | the file already on your Desktop (`MALVOYA_SECRET_DATA_ENCRYPTION_KEY.txt`), if not added yet |
| `GOOGLE_CLIENT_ID` | ✅ set | Google sign-in | already done |
| `ANDROID_APP_SHA256` | 🟡 upload key set | Android App Links | after the first Play upload, add Play's app-signing SHA-256, comma-separated |
| `APPLE_TEAM_ID` | P2 | iPhone universal links | Apple Developer → Membership |
| Prices: `DELIVERY_FEE_*`, `SERVICE_FEE_*`, `SMALL_ORDER_*`, commission per shop in admin | **P0 decision** | today's defaults lose money on every delivery | your choice; see the Fair Launch package |
| `DELIVERY_SLOTS` | P2 | evening delivery slots | e.g. `18:00-20:00` once you can staff them |
| `SENTRY_DSN` | P1 | server error reports | sentry.io (free tier) |
| `REDIS_URL`, `WORKER_MODE` | P2 | several servers and a background worker | only when traffic needs it (scaling plan) |
| `MIN_BUILD_*`, `MAINTENANCE_MESSAGE` | when needed | force old apps to update, or pause ordering | set only when needed |

### 2c. After setting them
Open **admin → System**. It lists everything still blocking real orders in plain language. When it says **"Ready for orders"**, the server side is complete.

## 3. Firebase (project `mivia-4f159`)
| Step | Priority | Status |
|---|---|---|
| Three Android apps registered, `google-services.json` in each app | — | ✅ |
| Service-account key → Render `FIREBASE_SERVICE_ACCOUNT` | **P0** | ❌ |
| `FIREBASE_PROJECT_ID` on Render | **P0** | check |
| Authentication → Sign-in method → **Phone** on | **P0** | check |
| SHA-1 + SHA-256 of the upload key for each app; Play's app-signing key after the first upload | **P0** | ❌ |
| SMS region policy: Finland and EU only | P1 | ❌ |
| App Check with Play Integrity | P1 | ❌ |
| Budget alert in Google Cloud billing (e.g. 20 €/month) | P1 | ❌ |
| Crashlytics enabled (the apps get the code in the current round) | P1 | ❌ |
| iOS: 3 iOS apps, `GoogleService-Info.plist` on the Mac, APNs key, Apple sign-in on | P1 (iPhone) | ❌ |
| Remove the old `com.example.mivia_app` entry | P2 | optional |

## 4. Stripe
| Step | Priority |
|---|---|
| Activate Stripe live in the company's name; Connect platform profile (marketplace, Express accounts) | P0 |
| Live keys and webhook secret on Render (2b) | P0 |
| Customer app: the publishable key switched from `pk_test_` to `pk_live_` in a new build | P0 |
| Payment methods: cards now; then Google Pay / Apple Pay, MobilePay and Klarna in the Stripe dashboard | P1 |
| Stripe Radar rules and statement descriptor "MALVOYA" | P1 |
| Keep a balance buffer of about 2 weeks of courier pay | P1 |

## 5. The apps
| Step | Priority | Status |
|---|---|---|
| Install 1.8.0 on a real Android phone; test order with card 4242 4242 4242 4242, a return, forgot password, a store order and a courier job | **P0** | ❌ |
| Crash reports (Crashlytics) | P1 | building now |
| Google Play account, three listings, internal test, then the 14-day closed test with 12+ testers | P0 for Play | ❌ |
| iPhone: build on the Mac (docs/ios/MAC-SETUP.md), Apple Developer account, TestFlight | P1 | ❌ |
| Switch the website's download page to the real store links | P1 | after listings |

## 6. Legal and business
| Step | Priority |
|---|---|
| Register the Oy (Y-tunnus, VAT, prepayment register), business bank account | P0 |
| Fill every `[PLACEHOLDER]` in `legal/` (company name, Y-tunnus, address, contact email), then publish the versions in admin → Legal | P0 |
| Lawyer review of the terms, seller terms, courier agreement, privacy policy | P0 |
| Insurance: liability, goods in transit, courier accident cover | P0 |
| Decide the courier model under the platform-work law (from 2 Dec 2026) | P0 |
| Accountant: VAT agent model, bookkeeping | P0 |
| Register on the EU Safety Gate portal; product-safety contact | P1 |
| Trademark search and filing for "Malvoya"; own domain | P1 |

## 7. Operations on day one
| Step | Priority |
|---|---|
| Create your admin account on the live server | P0 |
| 15+ shops signed, approved, with products and opening hours | P0 |
| 4–6 couriers approved, with shifts for the opening hours | P0 |
| 20 real-money test orders with friends (including one return, one failed delivery, one pickup) | P0 |
| Daily 10-minute check of admin → System, Support and Moderation | P1 |

## 8. The shortest path to "works from day one"
1. **This week:** health check path, Cloudinary, SMTP, the Firebase key and project ID on Render; install 1.8.0 and test it on your phone.
2. **Next 2 weeks:** company registration, Google Play account and internal test, prices decided, lawyer and insurance quotes.
3. **Then:** Stripe live, the webhook secret, the final legal texts; the 14-day Play test; the iPhone build on the Mac.
4. **Launch:** admin → System says "Ready for orders"; first shops and couriers in one district; 20 test orders; open to the waiting list.
