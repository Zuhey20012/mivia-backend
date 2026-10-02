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

Backend changes are verified with the end-to-end suite in `backend/test/e2e/` (162 checks: security, payments, orders, couriers, drops, pricing, payouts, reviews, returns, GDPR, support, legal). It runs the real API against a throwaway Postgres, Stripe's `stripe-mock` and a small Cloudinary mock; see its README. Add checks there when you add behaviour. Flutter apps: `flutter analyze` must report no issues.

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

- Render web service `malvoya-api-n065` (Oregon; auto-deploys every push to `master`). The local checkout usually sits on branch `security-hardening`, so push with `git push origin HEAD:master HEAD:security-hardening`.
- Admin panel: Render static site `malvoya-admin` at https://malvoya-admin.onrender.com (auto-deploys from `master`, build `cd malvoya_admin && npm ci && npm run build`, publishes `malvoya_admin/dist`, `VITE_API_URL` set on the service). It uses `HashRouter` (`/#/couriers`) because the static site has no SPA rewrite rule. The API's `ALLOWED_ORIGINS` lists `https://malvoya-admin.onrender.com`, `https://admin.malvoya.com` and `http://localhost:5173` (local `npm run dev` with `malvoya_admin/.env.local`). The database `malvoya-database` is also in Oregon. `render.yaml` targets **Frankfurt** for GDPR reasons. Render cannot move a service between regions, so moving means creating a new service and database and migrating the data.
- Prisma 7: the connection URL lives in `backend/prisma.config.ts`, not in `schema.prisma`. `PrismaClient` is created with the `@prisma/adapter-pg` driver adapter (`src/lib/prisma.ts`). The Render build needs `npm ci --include=dev`, because `NODE_ENV=production` would otherwise skip the TypeScript compiler and the Prisma CLI.
- Migrations: production was created with `db push`, then baselined by marking `20260419164539_init` as applied. That file's SQL has since been replaced with the real pre-2026-09-24 baseline (`fc96b60`), so `migrate deploy` on an empty database builds exactly `schema.prisma`; check with `npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma` (expects "No difference detected"). Add schema changes as new migrations and never edit applied ones. The only schema is `backend/prisma/schema.prisma`.

## Backend architecture

- `src/index.ts`: the Stripe webhook router is mounted **before** `express.json()`, because it needs the raw body. Courier routes are mounted before order routes, and every `:id` route uses `(\\d+)` so paths like `/orders/available` are never captured. `trust proxy` is set to 1 for Render.
- Module pattern: `src/modules/<name>/{routes,controller,service,schema}.ts`. Zod validates every body. Responses are `{ ok: true, … }` or `{ ok: false, error }`. Services throw `AuthError` or `OrderError` with an HTTP status; controllers map them.
- Auth: 15-minute access JWT (`typ: "access"`, HS256) plus a 7-day single-use refresh JWT, stored **SHA-256-hashed** in `RefreshToken`. All login paths go through `modules/auth/session.ts#issueSession`. Register never touches existing accounts. Verified sign-ins (Google, Apple, Firebase phone, one-time code) never open an account made by `/register` (bcrypt password, email/phone never proven); they get 409 from `auth.service.ts#assertVerifiedSignInAllowed`, so nobody can pre-register someone else's address. To use Google with such an account, the signed-in user links it (`POST /auth/google/link`, a "Google account" tile in each app's account settings): `User.googleSub` then opens that account on Google sign-in whatever its email, and sessions report `user.googleLinked`. Only password accounts can unlink (`DELETE /auth/google/link`); account deletion clears the link. Roles: `CUSTOMER | VENDOR | COURIER | ADMIN`. `ADMIN` is never self-assignable. Social sign-in (Google, or Firebase phone/Apple) accepts a `role` for **new** accounts only.
- `Courier` is a separate table linked by `Courier.userId`. Couriers need `isApproved` (set by an admin) before they get jobs. `modules/orders/access.ts#getOrderRelation` is the single authorisation check deciding who may see or act on an order (customer / vendor / assigned courier / admin). Both HTTP and sockets use it.
- **Order lifecycle** (`orders.service.ts` `TRANSITIONS`): `PENDING` (created, awaiting payment) → the **Stripe webhook** sets `paymentStatus=SUCCEEDED` (the only place an order becomes paid) → the vendor accepts (`CONFIRMED`) or declines (`CANCELLED` with an automatic refund) → `PROCESSING` → the assigned courier moves it to `SHIPPED` (picked up) and then `DELIVERED` (sets `deliveredAt`). Stock is reserved with conditional decrements at creation and restocked on cancellation. Money is integer cents in EUR. `utils/pricing.ts#deliveryFeeForDistance` is used by both the store list and checkout, so the displayed fee always matches the charged one.
- Returns: the 14-day withdrawal window counts from `deliveredAt`. `PATCH /returns/:id/status` with `REFUNDED` issues a real Stripe refund. Deleting an account **anonymises** the user and keeps orders, as the Accounting Act requires.
- Dispatch (`services/dispatchService.ts`): after the vendor accepts, the order is offered via socket to approved online couriers within 7.5 km, nearest first; otherwise to all online couriers. The first courier to accept wins (conditional update). Nothing is auto-assigned.
- Sockets (`lib/socket.ts`): JWT handshake. Rooms are joined only after `getOrderRelation` passes. `user:`, `store:`, `courier:` and `couriers` rooms are joined server-side from the token. Only the assigned courier can emit a location for an order. Chat is relayed and not stored.
- Notifications (`services/notificationDeliveryService.ts`): the server sends email/SMS only on real events (payment confirmed, status changes, OTP). Without SMTP/Twilio configured, production sends nothing and development logs the message. Emails are fi/en and HTML-escaped; the seller is named as the seller, not Malvoya.
- OTP codes are stored hashed in the `OtpCode` table.
- Errors: new modules throw `ApiError(message, status)` from `lib/errors.ts` and reply through `sendError`; the message must be safe to show users.
- **Media** (`lib/cloudinary.ts`, `modules/media`): the apps upload straight to Cloudinary with a one-time signature from `POST /media/sign`. Each kind (`product_image`, `store_image`, `drop_video`, `drop_image`, `delivery_proof`, `avatar`) has an owner-scoped folder prefix; anything the apps send back is checked with `verifyOwnedUpload` (Cloudinary's response signature + prefix). Apps never send raw URLs of their own; product/store image URLs must be in the owner's folder. Delivery proofs are `authenticated` (private, signed URLs) and purged after 30 days. The secret never leaves the server. Without `CLOUDINARY_*` env vars uploads return 503.
- **Drops** (`modules/drops`): shoppable videos/photos. Videos stay `PROCESSING` until Cloudinary's signed webhook (`/api/v1/media/cloudinary/notify`, raw body, mounted before `express.json`) or the scheduler confirms the HLS rendition. Feed ranking is explainable and non-profiling (freshness, engagement, distance, rating; `RANKING_EXPLANATION`, DSA Art. 27) with a snapshot cursor for stable paging; `latest` is chronological. Likes are unique per user, views are de-duplicated per viewer per day (`DropView`). Reports (DSA Art. 16) auto-hide a drop after three distinct signed-in reporters; admin removal requires a reason and emails the store a statement of reasons. Public share pages at `/d/:id`.
- **Pricing** (`modules/products/pricing.ts`): every sale price is recorded in `PriceChange`. A "was" price is shown only when it is the lowest price of the 30 days before the latest reduction (Omnibus); never compute discounts in the apps. Public products expose `inStock` flags, not stock counts. Products with options (`ProductVariant`) keep `stockQuantity` = sum of option stock.
- **Payouts** (`modules/payouts`): Stripe Connect Express. On `DELIVERED`, `createPayoutsForOrder` makes a courier payout (released now) and a store payout (released after `storePayoutHoldDays` = 15). `processDuePayouts` transfers with `source_transaction` and an idempotency key per payout. Refunds before release reduce the store payout (`adjustStorePayoutForRefund`). Onboarding and KYC happen on Stripe's pages.
- **Delivery handover:** couriers complete orders only via `POST /orders/:id/deliver` (`IN_PERSON`, or `PHOTO` with a verified upload), recording the handover position; `PATCH status DELIVERED` is refused for couriers.
- **Push** (`lib/push.ts`): FCM via `FIREBASE_SERVICE_ACCOUNT`; service messages only (orders, offers, drops, payouts). Tokens in `DeviceToken`, dead tokens pruned.
- **Background jobs** (`services/scheduler.ts`): payouts, video-processing checks, delivery-photo purge, expired OTP cleanup. Each job takes a lease row in `JobLease`, so several instances never run the same job at once. `DISABLE_SCHEDULER=true` turns them off on an instance.
- Verified reviews (`modules/me`): only for delivered orders, once per order, within 30 days; store/courier ratings are recomputed from non-hidden reviews. Favourites and push devices live under `/me/*`.
- Support (`modules/support`) stores requests from all apps (admin panel → Support) and emails the team when SMTP is set. Legal pages (`modules/legal`) render `legal/*.md` at `/legal/{privacy,terms,sellers,couriers}`; the apps link there, and it is the Play privacy-policy URL.

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

The simulated escrow, dispatch engine, telemetry service, "AI garment inspection" (RaaS/MCP) and BullMQ worker were deleted in September 2026 because they faked behaviour. Also removed from the apps: invented discounts/likes/sizes in the feed, locally-stored "drops", fake GPS proof, VoIP/SMS relays, fake support tickets and guarantees, keyword bots labelled "AI", pre-ticked consent switches for tracking that does not exist, and hard-coded delivery fees/ratings. Don't restore them from git history.

## Flutter app conventions

- Shared per-app helpers in `lib/core/`: `api_client.dart` (session, one retry after refresh, user-readable errors — use it for new calls instead of raw `http`), `push_service.dart` (FCM token registered after sign-in, removed via `AuthService.beforeLogout`), `strings.dart` (`tr(context, en, fi)` for new copy, `euro()`), `legal_links.dart`, and in store/courier `media_upload.dart` (signed direct uploads with progress).
- Customer: `DeliveryLocation` (pinned coordinates of the active address) drives store ranking, fees and ETAs and is sent with orders; the Drops tab (`screens/drops_feed.dart`) preloads ±1 HLS videos and reports views; `screens/catalogue.dart` is the search; `screens/order_detail.dart` is live tracking. Map tiles are OpenStreetMap (never scrape Google tiles).
- Courier: `CourierTelemetryService` shares position only while online, through an Android foreground service (visible notification); `setActiveOrder` ties it to the carried order.
- Each app has `lib/auth_service.dart` built from one shared design. `kAppRole` is set per app, and accounts with another role are refused at sign-in. Tokens live in `flutter_secure_storage`. The access token is refreshed automatically a minute before it expires. Phone sign-in = Firebase verifies the SMS code, then the Firebase ID token is exchanged at `/auth/phone`. Never derive passwords or fake sessions on the client.
- The apps never ask the server to send messages, and never report success for something the server rejected (no "saved locally" fallbacks).
- Every app lets the user delete the account in-app (Play requirement): customer via Privacy → Delete account, store and courier via `core/delete_account_tile.dart`. Courier location sharing is stopped by an `AuthService.beforeLogout` hook, so it ends with any sign-out. Profile name changes go through `PATCH /me/profile`.
- Payments: the customer app only opens Stripe's PaymentSheet with the server's `clientSecret`. **Never add card, CVV or IBAN input fields**; that would put the app in PCI-DSS scope.
- State: `provider` `ChangeNotifier`s. The customer `features/order_tracking` uses `flutter_bloc` with a clean-architecture split. Localization is hand-rolled `AppLocalizations` in `Malvoya_customer/lib/l10n.dart` (fi/en). New user-facing copy is written as "Finnish / English".

## Brand

- Logo: the "Thread M". `lib/widgets/brand_mark.dart` in each app has `BrandMark` and `BrandTile`, drawn with `CustomPaint`. Icon PNG sources are in `assets/brand/`; regenerate launcher icons and splash with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- Colours: Malva `#6D2E8C` (customer), Moss `#2E6B4F` (store), Lingon `#C2412D` (courier), Birch `#F6F3EE` (light background) and Night `#17131C` (dark background). Status colours: green `#248A52`, red `#D93025`, amber `#E08A00`.
- Style: system fonts (no custom fonts), iOS-style page transitions on iOS, flat surfaces with hairline borders, 14 px radius on controls, 52 px buttons. The customer app follows the phone's light/dark setting until the user picks a theme. Don't reintroduce neon gradients, glows or emoji in UI copy.
- Play Store: bump `version:` in each `pubspec.yaml` (the `+N` build number must increase with every upload; `1.2.0+4` is the current build).

## Compliance context (Finland / EU)

GDPR: data minimisation, retention, export and delete are implemented. The Oregon hosting still needs to move to the EU. The Accounting Act requires keeping order records. The Consumer Protection Act chapter 6 gives a 14-day withdrawal right and a refund of the delivery fee. PSD2 SCA is handled by Stripe. The Platform Work Directive (from Dec 2026) requires transparent, non-automated courier management. DAC7 requires seller reporting. Omnibus: `Store.sellerType` (BUSINESS/PRIVATE, with Y-tunnus for businesses) is shown to shoppers and locked after verification; "was" prices follow the 30-day rule; reviews are verified purchases. DSA: notice-and-action, statements of reasons, trader information on product and store pages, recommender transparency. No Y-tunnus exists yet, so never invent company names or business IDs. Legal texts in `legal/` use `[PLACEHOLDERS]`.
