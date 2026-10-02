# End-to-end test

Runs the real API against a throwaway Postgres, Stripe's official `stripe-mock` and a small
Cloudinary mock, and checks security, payments, orders, couriers, drops, pricing, payouts,
reviews, returns, GDPR, support and legal pages (195 checks).

```bash
# 1. Throwaway database and Stripe mock
docker run -d --name malvoya-test-db -e POSTGRES_PASSWORD=test -e POSTGRES_DB=malvoya_test -p 55432:5432 postgres:15
docker run -d --name malvoya-stripe-mock -p 12111:12111 stripe/stripe-mock:latest

# 2. Schema (fresh database)
DATABASE_URL=postgresql://postgres:test@localhost:55432/malvoya_test npx prisma db push

# 3. Mock, API and test (from backend/)
node test/e2e/cloudinary_mock.js &
npm run build && (set -a; . test/e2e/test.env; set +a; node dist/index.js &)
node test/e2e/e2e.js
```

The test uses `docker exec malvoya-test-db psql` for a few direct database checks.
