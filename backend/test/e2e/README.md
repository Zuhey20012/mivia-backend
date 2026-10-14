# End-to-end test

Runs the real API against a throwaway Postgres, Stripe's official `stripe-mock` and a small
Cloudinary mock, and checks security, payments, orders, couriers, drops, pricing, payouts,
reviews, returns, GDPR, support, legal pages, fees, price quotes, promo codes, courier pay and catalogue
import (324 checks).

```bash
# 1. Throwaway database and Stripe mock
docker run -d --name malvoya-test-db -e POSTGRES_PASSWORD=test -e POSTGRES_DB=malvoya_test -p 55432:5432 postgres:15
docker run -d --name malvoya-stripe-mock -p 12111:12111 stripe/stripe-mock:latest

# 2. Schema (fresh database)
DATABASE_URL=postgresql://postgres:test@localhost:55432/malvoya_test npx prisma migrate deploy

# 3. Mock, API and test (from backend/)
node test/e2e/cloudinary_mock.js &
npm run build && (set -a; . test/e2e/test.env; set +a; node dist/index.js &)
node test/e2e/e2e.js
```

The test uses `docker exec malvoya-test-db psql` for a few direct database checks. For the fee checks it
starts a second API instance itself (`dist/index.js` on port 4556, same database, scheduler off) with the
`SERVICE_FEE_*` / `SMALL_ORDER_*` env vars set, `COURIER_PAY_MODE=fee_share` and Cloudinary switched off (import 503),
and stops it again; so run `npm run build` first. The courier-pay checks also load `dist/utils/courierPay.js` directly.

The catalogue-import checks start a tiny Shopify mock (`/products.json`) on port 12223 inside the test; `test.env`
sets `IMPORT_ALLOW_HOSTS=localhost:12223` so the SSRF guard lets the API reach it (test only; ignored when
`NODE_ENV=production`). The Cloudinary mock also accepts signed server-side uploads from a remote URL and lists
them at `/__uploads`.
