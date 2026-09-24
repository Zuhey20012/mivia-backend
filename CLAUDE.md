# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Malvoya is a hyperlocal fashion marketplace for Finland: people buy, rent and return clothes, and local couriers deliver them. One Node/TypeScript API serves three Flutter apps (customer, vendor, courier) and a React admin panel. The project is pre-launch: there are no real vendors, couriers or customers yet, and the production database contains only test accounts.

`C:\Users\Zuhey\Desktop\Malvoya_APKs` and `Malvoya_Apps` hold only build outputs (`.apk` / `.aab`), not source.

## Repository layout and git quirks

| Path | What it is |
|---|---|
| `backend/` | Express + Prisma 7 + Socket.io API (the live backend) |
| `Malvoya_customer/` | Flutter customer app (largest, ~26k lines) |
| `malvoya_vendor/`, `malvoya_courier/` | Flutter store and courier apps |
| `malvoya_admin/` | React 19 + Vite + Tailwind admin panel |
| `legal/` | Privacy policy, customer terms, seller terms, courier agreement (drafts with `[PLACEHOLDERS]`) |
| `functions/` | Firebase Cloud Functions over Firestore. **Not wired up** (no `firebase.json`; the apps use the Postgres API). Treat as dead code |
| `mivia_app/`, `mivia_courier/`, `mivia_vendor/` | Old build leftovers from the previous "Mivia" name. Ignore them |

- The outer repo (`master`) and `backend/` (a **nested `.git`**, branch `main`) both push to `github.com/Zuhey20012/mivia-backend`, with unrelated histories. Commit from the **outer** repo. The live Render service builds `master` with `rootDir: backend`.
- **The GitHub repo is public.** Never commit secrets. `.env` files and `backend/create-admin.js` are git-ignored.

## Commands

Backend (`cd backend`). Prisma 7 requires Node ^20.19, ^22.12 or ≥24.
```bash
npm install
npm run dev                  # ts-node-dev on :4000
npm run build                # tsc -> dist/  (set NODE_OPTIONS=--max-old-space-size=1536 on low-RAM machines)
npm start
npx prisma generate
npx prisma migrate dev --name <change>
npx prisma migrate deploy
SEED_ADMIN_EMAIL=… SEED_ADMIN_PASSWORD=… npx prisma db seed   # creates the first admin; nothing is hardcoded
docker compose up db         # local Postgres 16 (backend/docker-compose.yml; the root compose file includes it)
```
The backend **refuses to start** without `JWT_SECRET` and `JWT_REFRESH_SECRET`: each needs ≥32 characters and they must differ. In production it also refuses `ALLOWED_ORIGINS=*`. All env vars are listed in `backend/.env.example`.

There are no unit-test files. Verify changes by running the API against a throwaway Postgres container. Apply the baseline schema plus migrations, then exercise flows over HTTP and Socket.io.

Flutter apps (inside each app folder):
```bash
flutter pub get
flutter analyze --no-pub lib     # must report "No issues found"
flutter run
flutter build appbundle --release
```
Release signing reads `android/key.properties`, which is untracked. Application IDs are `com.malvoya.{customer,vendor,courier}`. The API URL and the Stripe publishable key (test mode) are in each app's `lib/config/constants.dart`.

Admin (`cd malvoya_admin`): `npm run dev`, `npm run build`, `npm run lint`. The API URL comes from `VITE_API_URL`.

## Deployment

- Render web service `malvoya-api-n065` (Oregon, auto-deploy off, so deploys are manual). The database `malvoya-database` is also in Oregon. `render.yaml` targets **Frankfurt** for GDPR reasons. Render cannot move a service between regions, so moving means creating a new service and database and migrating the data.
- Prisma 7: the connection URL lives in `backend/prisma.config.ts`, not in `schema.prisma`. `PrismaClient` is created with the `@prisma/adapter-pg` driver adapter (`src/lib/prisma.ts`). The Render build needs `npm ci --include=dev`, because `NODE_ENV=production` would otherwise skip the TypeScript compiler and the Prisma CLI.
- Migrations: production was created with `db push` and records only `20260419164539_init` as applied. That file's SQL is **stale** (old Vendor/Order tables), so `migrate deploy` on a fresh database produces the wrong schema. A correct baseline is `prisma migrate diff --from-empty --to-schema prisma/schema.prisma --script` of the pre-2026-09-24 schema. Replacing the init SQL with it is pending the owner's OK. `20260924120000_security_hardening` applies cleanly on top of production.

## Backend architecture

- `src/index.ts`: the Stripe webhook router is mounted **before** `express.json()`, because it needs the raw body. Courier routes are mounted before order routes, and every `:id` route uses `(\\d+)` so paths like `/orders/available` are never captured. `trust proxy` is set to 1 for Render.
- Module pattern: `src/modules/<name>/{routes,controller,service,schema}.ts`. Zod validates every body. Responses are `{ ok: true, … }` or `{ ok: false, error }`. Services throw `AuthError` or `OrderError` with an HTTP status; controllers map them.
- Auth: 15-minute access JWT (`typ: "access"`, HS256) plus a 7-day single-use refresh JWT, stored **SHA-256-hashed** in `RefreshToken`. All login paths go through `modules/auth/session.ts#issueSession`. Register never touches existing accounts. Roles: `CUSTOMER | VENDOR | COURIER | ADMIN`. `ADMIN` is never self-assignable. Social sign-in (Google, or Firebase phone/Apple) accepts a `role` for **new** accounts only.
- `Courier` is a separate table linked by `Courier.userId`. Couriers need `isApproved` (set by an admin) before they get jobs. `modules/orders/access.ts#getOrderRelation` is the single authorisation check deciding who may see or act on an order (customer / vendor / assigned courier / admin). Both HTTP and sockets use it.
- **Order lifecycle** (`orders.service.ts` `TRANSITIONS`): `PENDING` (created, awaiting payment) → the **Stripe webhook** sets `paymentStatus=SUCCEEDED` (the only place an order becomes paid) → the vendor accepts (`CONFIRMED`) or declines (`CANCELLED` with an automatic refund) → `PROCESSING` → the assigned courier moves it to `SHIPPED` (picked up) and then `DELIVERED` (sets `deliveredAt`). Stock is reserved with conditional decrements at creation and restocked on cancellation. Money is integer cents in EUR. `utils/pricing.ts#deliveryFeeForDistance` is used by both the store list and checkout, so the displayed fee always matches the charged one.
- Returns: the 14-day withdrawal window counts from `deliveredAt`. `PATCH /returns/:id/status` with `REFUNDED` issues a real Stripe refund. Deleting an account **anonymises** the user and keeps orders, as the Accounting Act requires.
- Dispatch (`services/dispatchService.ts`): after the vendor accepts, the order is offered via socket to approved online couriers within 7.5 km, nearest first; otherwise to all online couriers. The first courier to accept wins (conditional update). Nothing is auto-assigned.
- Sockets (`lib/socket.ts`): JWT handshake. Rooms are joined only after `getOrderRelation` passes. `user:`, `store:`, `courier:` and `couriers` rooms are joined server-side from the token. Only the assigned courier can emit a location for an order. Chat is relayed and not stored.
- Notifications (`services/notificationDeliveryService.ts`): the server sends email/SMS only on real events (payment confirmed, status changes, OTP). Without SMTP/Twilio configured, production sends nothing and development logs the message. Emails are fi/en and HTML-escaped; the seller is named as the seller, not Malvoya.
- OTP codes are kept hashed in an in-memory `Map` (single instance only).

### Scaling foundations (keep them when changing code)

- **Stateless instances:** no user state in process memory. Sign-in codes are in the `OtpCode` table. Sessions are JWT plus hashed refresh tokens in the DB. Before running more than one instance, two pieces are still per-instance and need Redis: the rate limiter (`express-rate-limit`'s default memory store) and Socket.io rooms (add `@socket.io/redis-adapter`).
- **Indexes:** every foreign key and list query path has an `@@index` (migration `20260925090000_scale_indexes_and_otp`). Add one whenever you add a new `where`/`orderBy` path.
- **List endpoints are bounded** (`take` limits, paginated store and product lists). Never return unbounded lists.
- **Operations:**
  - `/health` is liveness and `/health/ready` checks the database.
  - Graceful SIGTERM shutdown enables zero-downtime deploys.
  - `pino-http` logs one line per request with an `x-request-id`; auth headers are redacted, and bodies and PII are never logged.
  - `compression` is on.
  - The pg pool size is `DB_POOL_MAX` (default 10) per instance.

### Removed on purpose

The simulated escrow, dispatch engine, telemetry service, "AI garment inspection" (RaaS/MCP) and BullMQ worker were deleted in September 2026 because they faked behaviour. Don't restore them from git history.

## Flutter app conventions

- Each app has `lib/auth_service.dart` built from one shared design. `kAppRole` is set per app, and accounts with another role are refused at sign-in. Tokens live in `flutter_secure_storage`. The access token is refreshed automatically a minute before it expires. Phone sign-in = Firebase verifies the SMS code, then the Firebase ID token is exchanged at `/auth/phone`. Never derive passwords or fake sessions on the client.
- The apps never ask the server to send messages, and never report success for something the server rejected (no "saved locally" fallbacks).
- Payments: the customer app only opens Stripe's PaymentSheet with the server's `clientSecret`. **Never add card, CVV or IBAN input fields**; that would put the app in PCI-DSS scope.
- State: `provider` `ChangeNotifier`s. The customer `features/order_tracking` uses `flutter_bloc` with a clean-architecture split. Localization is hand-rolled `AppLocalizations` in `Malvoya_customer/lib/l10n.dart` (fi/en). New user-facing copy is written as "Finnish / English".

## Brand

- Logo: the "Thread M". `lib/widgets/brand_mark.dart` in each app has `BrandMark` and `BrandTile`, drawn with `CustomPaint`. Icon PNG sources are in `assets/brand/`; regenerate launcher icons and splash with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- Colours: Malva `#6D2E8C` (customer), Moss `#2E6B4F` (store), Lingon `#C2412D` (courier), Birch `#F6F3EE` (light background) and Night `#17131C` (dark background). Status colours: green `#248A52`, red `#D93025`, amber `#E08A00`.
- Style: system fonts (no custom fonts), iOS-style page transitions on iOS, flat surfaces with hairline borders, 14 px radius on controls, 52 px buttons. The customer app follows the phone's light/dark setting until the user picks a theme. Don't reintroduce neon gradients, glows or emoji in UI copy.
- Play Store: bump `version:` in each `pubspec.yaml` (the `+N` build number must increase with every upload; `1.1.0+2` was the first build after the rebrand).

## Compliance context (Finland / EU)

GDPR: data minimisation, retention, export and delete are implemented. The Oregon hosting still needs to move to the EU. The Accounting Act requires keeping order records. The Consumer Protection Act chapter 6 gives a 14-day withdrawal right and a refund of the delivery fee. PSD2 SCA is handled by Stripe. The Platform Work Directive (from Dec 2026) requires transparent, non-automated courier management. DAC7 requires seller reporting. The Omnibus rule requires showing whether a seller is a trader, which is **not yet modelled** (`Store` needs a trader flag). No Y-tunnus exists yet, so never invent company names or business IDs. Legal texts in `legal/` use `[PLACEHOLDERS]`.
