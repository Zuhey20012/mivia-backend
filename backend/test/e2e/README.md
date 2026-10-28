# End-to-end test

Runs the real API against a throwaway Postgres, Stripe's official `stripe-mock` and a small
Cloudinary mock, and checks security, payments, orders, couriers, drops, pricing, payouts,
reviews, returns (also per item), GDPR, support, legal pages, fees, price quotes, promo codes, courier pay,
catalogue import (Shopify, WooCommerce, CSV), Reserve & collect (pickup), per-store commission, referrals, share pages and App Links,
scheduled delivery slots, DAC7 seller tax data and report, monthly store statements and owner analytics, and (2.10) forgot/reset/change
password and session revocation, agreement acceptance, language storage, finishing unpaid checkouts, store cancel reasons,
return notes and notifications, product deletion and the store's paged catalogue, "courier cannot deliver" and return to the
shop (items-only refund, courier payout), order chat history, blocking and review reports, approval messages, account-deletion
media clean-up, signed statement links and DAC7 reminders, and (2.11) legal versions, acceptance records with copies and signed
links, 428 enforcement, publishing with notice periods, the PRH/YTJ business check (local mock) and onboarding checklists, and
(2.12) the category taxonomy and its counts within reach, search by category, audience, age group and attribute facets,
per-template publishing rules (422 with field-level FI/EN messages), unit prices per litre/kg and the under-50 ml/g
exemption, removal of the eco claim, certificates and their admin verification, product reports, recalls with direct buyer
notices and the public recalls page, the hygiene-seal return rules, import category mapping, collections, admin categories,
payout onboarding before approval, the empty DELIVERY_SLOTS default and the System connection test, and (2.13) admin two-step
sign-in: set-up, encrypted secret, one-time codes and recovery codes, lockout, the `ADMIN_MFA_REQUIRED` gate on the second instance and security.txt, zero commission by default, the audit fixes (delivery reach, closed rejected returns, rentals off, chat room and socket sessions) the /contact form and photo drops with sound, and (2.14) reels: the licensed sound library (admin-only signing, licence and rights required, 180 s limit, audited edits incl. clearing fields, store search and paging, sound pages and use counts, inactive sounds), library or own sound and voice-over on video drops with MIX/REPLACE and trim checks, saves (saved list, counts, savedByMe) and "Not interested" (hidden from that user's feeds, store and sound lists, undo), and their data export and deletion (920 checks; one slot check only runs when a
today slot starts within the next hour or has passed, so the count can be one lower). The chat-purge and DAC7-reminder checks load
`dist/modules/orders/chat.js` and `dist/modules/sellers/taxReminders.js` directly (same database); the referral instance
on port 4556 runs with `NODE_ENV=production` and no SMTP, for the "password reset by email is not available" (503) check.

```bash
# 1. Throwaway database and Stripe mock
docker run -d --name malvoya-test-db -e POSTGRES_PASSWORD=test -e POSTGRES_DB=malvoya_test -p 56432:5432 postgres:15
docker run -d --name malvoya-stripe-mock -p 12111:12111 stripe/stripe-mock:latest

# 2. Schema (fresh database)
DATABASE_URL=postgresql://postgres:test@localhost:56432/malvoya_test npx prisma migrate deploy

# 3. Mock, API and test (from backend/)
node test/e2e/cloudinary_mock.js &
npm run build && (set -a; . test/e2e/test.env; set +a; node dist/index.js &)
node test/e2e/e2e.js
```

The test uses `docker exec malvoya-test-db psql` for a few direct database checks. For the fee checks it
starts a second API instance itself (`dist/index.js` on port 4556, same database, scheduler off) with the
`SERVICE_FEE_*` / `SMALL_ORDER_*` env vars set, `COURIER_PAY_MODE=fee_share` and Cloudinary switched off (import 503),
and stops it again; later it starts it once more with `REFERRAL_DISCOUNT_CENTS` / `REFERRAL_REWARD_CENTS` and
`ANDROID_APP_SHA256` set for the referral and assetlinks checks. The first instance also runs with `DELIVERY_SLOTS=00:00-23:59`,
`SCHEDULED_DELIVERY_DISCOUNT_CENTS=100` and no `DATA_ENCRYPTION_KEY` (scheduled-discount and "tax IDs cannot be saved" checks);
`test.env` has a throwaway `DATA_ENCRYPTION_KEY`. Since 2.12 scheduled delivery is off unless `DELIVERY_SLOTS` is set, so `test.env` sets the slots the test expects
(`17:00-19:00,19:00-21:00`) and `CATALOG_COLLECTION_MIN_ITEMS=2` (collections show from 2 nearby items instead of 8); the
referral instance runs with `DELIVERY_SLOTS=` (empty) to check the default. The import-mapping checks load
`dist/modules/catalog/matcher.js` directly. Start the Cloudinary mock fresh for every run (the import checks read its upload list). So run `npm run build` first. The courier-pay checks also load `dist/utils/courierPay.js` directly.

The business-check checks use a PRH/YTJ open-data mock the test starts on port 12224 (`test.env` sets
`PRH_API_TEST_HOST=localhost:12224`; never the real register). The legal-publishing checks start the second instance on
port 4556 with `LEGAL_DIR` pointing at a temporary copy of `legal/`, change texts there and publish them. If your `.env`
sets `REDIS_URL`, start the API and the test with `REDIS_URL=` (empty) so they run without Redis.

The catalogue-import checks start a tiny Shopify mock (`/products.json`, `/meta.json`) and then a WooCommerce REST API
mock (`/wp-json/wc/v3/...`, Basic-auth keys) on port 12223 inside the test; `test.env`
sets `IMPORT_ALLOW_HOSTS=localhost:12223` so the SSRF guard lets the API reach it (test only; ignored when
`NODE_ENV=production`). The Cloudinary mock also accepts signed server-side uploads from a remote URL and lists
them at `/__uploads`.
