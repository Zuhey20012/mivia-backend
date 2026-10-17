# Malvoya API route map

Generated on 17 October 2026 from `backend/src` (every `router.get/post/put/patch/delete` and the `app.use` mounts in `src/index.ts`). 164 routes. Paths under `/api/v1` are the JSON API; share pages, legal pages, App Links and health checks are at the root. Numeric parameters use `(\d+)` in the code and are left out here. "signed-in" = any role with a valid access token; `modules/orders/access.ts#getOrderRelation` then decides who may see or act on an order.

Mounts (index.ts): `/api/v1` payments and media routers before `express.json()` (raw body for webhooks); `/api/v1/auth`; `/api/v1/stores` (stores and sellers); `/api/v1` imports, products, courier (before orders), orders, drops, me, launch alerts, safety, referrals, app-config, payouts, support; `/api/v1/admin` (admin, moderation, promo codes); root: Drop share pages, share/App Links, legal pages, `/health`.

## Auth and account (16)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| POST | `/api/v1/auth/register` | public |  | `auth/auth.routes.ts:8` |
| POST | `/api/v1/auth/login` | public |  | `auth/auth.routes.ts:9` |
| POST | `/api/v1/auth/otp/send` | public |  | `auth/auth.routes.ts:10` |
| POST | `/api/v1/auth/otp/verify` | public |  | `auth/auth.routes.ts:11` |
| POST | `/api/v1/auth/google` | public |  | `auth/auth.routes.ts:12` |
| POST | `/api/v1/auth/google/link` | signed-in |  | `auth/auth.routes.ts:13` |
| DELETE | `/api/v1/auth/google/link` | signed-in |  | `auth/auth.routes.ts:14` |
| POST | `/api/v1/auth/phone` | public |  | `auth/auth.routes.ts:15` |
| POST | `/api/v1/auth/apple` | public |  | `auth/auth.routes.ts:16` |
| POST | `/api/v1/auth/password/forgot` | public |  | `auth/auth.routes.ts:18` |
| POST | `/api/v1/auth/password/reset` | public |  | `auth/auth.routes.ts:19` |
| POST | `/api/v1/auth/password/change` | signed-in |  | `auth/auth.routes.ts:21` |
| POST | `/api/v1/auth/refresh` | public | needs the single-use refresh token | `auth/auth.routes.ts:22` |
| POST | `/api/v1/auth/logout` | public | revokes the refresh token | `auth/auth.routes.ts:23` |
| DELETE | `/api/v1/auth/me` | signed-in |  | `auth/auth.routes.ts:25` |
| GET | `/api/v1/auth/me/data` | signed-in |  | `auth/auth.routes.ts:26` |

## Public catalogue and feed (no sign-in needed) (16)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/stores` | public |  | `stores/stores.routes.ts:17` |
| GET | `/api/v1/stores/:id` | public (optional sign-in) |  | `stores/stores.routes.ts:27` |
| GET | `/api/v1/stores/:storeId/products` | public (optional sign-in) |  | `products/products.routes.ts:8` |
| GET | `/api/v1/products/search` | public |  | `products/products.routes.ts:9` |
| GET | `/api/v1/products/:id` | public (optional sign-in) |  | `products/products.routes.ts:10` |
| GET | `/api/v1/drops/feed` | public (optional sign-in) |  | `drops/drops.routes.ts:26` |
| GET | `/api/v1/drops/ranking` | public |  | `drops/drops.routes.ts:35` |
| GET | `/api/v1/stores/:storeId/drops` | public (optional sign-in) |  | `drops/drops.routes.ts:43` |
| GET | `/api/v1/drops/:id` | public (optional sign-in) |  | `drops/drops.routes.ts:51` |
| POST | `/api/v1/drops/:id/view` | public (optional sign-in) |  | `drops/drops.routes.ts:103` |
| POST | `/api/v1/drops/:id/share` | public (optional sign-in) |  | `drops/drops.routes.ts:111` |
| POST | `/api/v1/drops/:id/report` | public (optional sign-in) | DSA Art. 16 notice | `drops/drops.routes.ts:122` |
| GET | `/api/v1/drops/:id/comments` | public (optional sign-in) |  | `drops/social.ts:193` |
| GET | `/api/v1/stores/:id/reviews` | public (optional sign-in) |  | `me/me.routes.ts:202` |
| GET | `/api/v1/app-config` | public | minimum build and maintenance gate | `appConfig/appConfig.routes.ts:33` |
| POST | `/api/v1/support` | public (optional sign-in) | stored for admin → Support | `support/support.routes.ts:28` |

## Customer app (7)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| POST | `/api/v1/orders` | customer | list depends on role | `orders/orders.routes.ts:15` |
| POST | `/api/v1/orders/quote` | customer | exact price before payment; creates nothing | `orders/orders.routes.ts:17` |
| POST | `/api/v1/orders/:id/cancel` | customer |  | `orders/orders.routes.ts:20` |
| GET | `/api/v1/orders/:id/payment` | customer |  | `orders/orders.routes.ts:30` |
| POST | `/api/v1/rentals` | customer | rental orders | `orders/orders.routes.ts:40` |
| POST | `/api/v1/returns` | customer |  | `orders/orders.routes.ts:45` |
| GET | `/api/v1/me/referral` | customer |  | `referrals/referrals.routes.ts:10` |

## Any signed-in user (36)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| POST | `/api/v1/chat/translate` | signed-in |  | `orders/courier.routes.ts:126` |
| GET | `/api/v1/orders` | signed-in | list depends on role | `orders/orders.routes.ts:18` |
| GET | `/api/v1/orders/:id` | signed-in | order relation checked (customer, shop, assigned courier, admin) | `orders/orders.routes.ts:19` |
| GET | `/api/v1/orders/:id/proof` | signed-in | delivery photo; relation checked | `orders/orders.routes.ts:25` |
| GET | `/api/v1/rentals` | signed-in | rental orders | `orders/orders.routes.ts:41` |
| GET | `/api/v1/rentals/:id` | signed-in |  | `orders/orders.routes.ts:42` |
| GET | `/api/v1/returns` | signed-in |  | `orders/orders.routes.ts:46` |
| GET | `/api/v1/returns/:id` | signed-in |  | `orders/orders.routes.ts:47` |
| GET | `/api/v1/orders/:id/messages` | signed-in |  | `orders/chat.ts:68` |
| POST | `/api/v1/orders/:id/messages` | signed-in |  | `orders/chat.ts:76` |
| POST | `/api/v1/drops/:id/like` | signed-in |  | `drops/drops.routes.ts:85` |
| DELETE | `/api/v1/drops/:id/like` | signed-in |  | `drops/drops.routes.ts:91` |
| POST | `/api/v1/drops/:id/comments` | signed-in |  | `drops/social.ts:200` |
| DELETE | `/api/v1/drops/:id/comments/:commentId` | signed-in |  | `drops/social.ts:208` |
| POST | `/api/v1/drops/:id/comments/:commentId/report` | signed-in |  | `drops/social.ts:215` |
| PUT | `/api/v1/stores/:id/follow` | signed-in |  | `drops/social.ts:223` |
| DELETE | `/api/v1/stores/:id/follow` | signed-in |  | `drops/social.ts:229` |
| PATCH | `/api/v1/me/profile` | signed-in |  | `me/me.routes.ts:18` |
| GET | `/api/v1/me` | signed-in |  | `me/me.routes.ts:41` |
| PATCH | `/api/v1/me` | signed-in |  | `me/me.routes.ts:53` |
| GET | `/api/v1/me/favorites` | signed-in |  | `me/me.routes.ts:69` |
| PUT | `/api/v1/me/favorites/:productId` | signed-in |  | `me/me.routes.ts:89` |
| DELETE | `/api/v1/me/favorites/:productId` | signed-in |  | `me/me.routes.ts:103` |
| POST | `/api/v1/me/devices` | signed-in |  | `me/me.routes.ts:117` |
| DELETE | `/api/v1/me/devices` | signed-in |  | `me/me.routes.ts:133` |
| POST | `/api/v1/orders/:id/review` | signed-in |  | `me/me.routes.ts:160` |
| GET | `/api/v1/orders/:id/review` | signed-in |  | `me/me.routes.ts:189` |
| GET | `/api/v1/me/launch-alert` | signed-in |  | `me/launchAlerts.ts:25` |
| PUT | `/api/v1/me/launch-alert` | signed-in |  | `me/launchAlerts.ts:32` |
| DELETE | `/api/v1/me/launch-alert` | signed-in |  | `me/launchAlerts.ts:46` |
| GET | `/api/v1/me/blocks` | signed-in |  | `me/safety.ts:107` |
| POST | `/api/v1/me/blocks` | signed-in |  | `me/safety.ts:113` |
| DELETE | `/api/v1/me/blocks/:userId` | signed-in |  | `me/safety.ts:121` |
| POST | `/api/v1/reviews/:id/report` | signed-in |  | `me/safety.ts:127` |
| POST | `/api/v1/media/sign` | signed-in | one-time Cloudinary upload signature | `media/media.routes.ts:43` |
| POST | `/api/v1/media/confirm` | signed-in |  | `media/media.routes.ts:58` |

## Shop app (27)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/stores/my` | store (VENDOR) |  | `stores/stores.routes.ts:18` |
| GET | `/api/v1/stores/my/products` | store (VENDOR) |  | `stores/stores.routes.ts:20` |
| POST | `/api/v1/stores` | store (VENDOR) |  | `stores/stores.routes.ts:28` |
| PATCH | `/api/v1/stores/:id` | store (VENDOR) |  | `stores/stores.routes.ts:29` |
| GET | `/api/v1/stores/my/tax-info` | store (VENDOR) |  | `sellers/sellers.routes.ts:12` |
| PUT | `/api/v1/stores/my/tax-info` | store (VENDOR) |  | `sellers/sellers.routes.ts:18` |
| GET | `/api/v1/stores/my/statements` | store (VENDOR) |  | `sellers/sellers.routes.ts:28` |
| GET | `/api/v1/stores/my/statements/:month.html` | store (VENDOR) |  | `sellers/sellers.routes.ts:36` |
| GET | `/api/v1/stores/my/statements/:month/link` | store (VENDOR) |  | `sellers/sellers.routes.ts:46` |
| POST | `/api/v1/products/import/shopify` | store (VENDOR) |  | `imports/imports.routes.ts:42` |
| POST | `/api/v1/products/import/woocommerce` | store (VENDOR) |  | `imports/imports.routes.ts:50` |
| POST | `/api/v1/products/import/csv` | store (VENDOR) |  | `imports/imports.routes.ts:59` |
| GET | `/api/v1/products/import` | store (VENDOR) |  | `imports/imports.routes.ts:70` |
| GET | `/api/v1/products/import/:id` | store (VENDOR) |  | `imports/imports.routes.ts:76` |
| POST | `/api/v1/products/import/:id/publish` | store (VENDOR) |  | `imports/imports.routes.ts:84` |
| POST | `/api/v1/products` | store (VENDOR) |  | `products/products.routes.ts:11` |
| PATCH | `/api/v1/products/:id` | store (VENDOR) |  | `products/products.routes.ts:12` |
| DELETE | `/api/v1/products/:id` | store (VENDOR) |  | `products/products.routes.ts:13` |
| POST | `/api/v1/products/:id/videos` | store (VENDOR) |  | `products/productVideos.ts:101` |
| DELETE | `/api/v1/products/:id/videos/:videoId` | store (VENDOR) |  | `products/productVideos.ts:109` |
| PATCH | `/api/v1/orders/:id/status` | store, courier, admin | service enforces who may do which transition | `orders/orders.routes.ts:22` |
| POST | `/api/v1/orders/:id/collect` | store (VENDOR) | pickup code; 5 wrong tries lock 15 min | `orders/orders.routes.ts:27` |
| POST | `/api/v1/orders/:id/returned-received` | store (VENDOR) |  | `orders/orders.routes.ts:35` |
| PATCH | `/api/v1/returns/:id/status` | store, admin |  | `orders/orders.routes.ts:48` |
| GET | `/api/v1/drops/mine` | store (VENDOR) |  | `drops/drops.routes.ts:37` |
| POST | `/api/v1/drops` | store (VENDOR) |  | `drops/drops.routes.ts:70` |
| DELETE | `/api/v1/drops/:id` | store (VENDOR) |  | `drops/drops.routes.ts:78` |

## Courier app (11)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/courier/me` | courier |  | `orders/courier.routes.ts:15` |
| GET | `/api/v1/orders/available` | courier |  | `orders/courier.routes.ts:31` |
| GET | `/api/v1/orders/unassigned` | courier |  | `orders/courier.routes.ts:37` |
| GET | `/api/v1/orders/courier/mine` | courier |  | `orders/courier.routes.ts:43` |
| PATCH | `/api/v1/orders/:id/assign-courier` | courier | accept a job; first courier wins | `orders/courier.routes.ts:49` |
| POST | `/api/v1/orders/:id/arrived-at-store` | courier |  | `orders/courier.routes.ts:57` |
| POST | `/api/v1/courier/status` | courier |  | `orders/courier.routes.ts:72` |
| POST | `/api/v1/courier/telemetry` | courier |  | `orders/courier.routes.ts:100` |
| POST | `/api/v1/orders/:id/deliver` | courier | in person or photo handover | `orders/orders.routes.ts:24` |
| POST | `/api/v1/orders/:id/delivery-problem` | courier |  | `orders/orders.routes.ts:32` |
| POST | `/api/v1/orders/:id/return-to-store` | courier |  | `orders/orders.routes.ts:33` |

## Payouts (shops and couriers) (4)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| POST | `/api/v1/payouts/onboarding` | store, courier |  | `payouts/payouts.routes.ts:9` |
| GET | `/api/v1/payouts/status` | store, courier |  | `payouts/payouts.routes.ts:15` |
| POST | `/api/v1/payouts/dashboard` | store, courier |  | `payouts/payouts.routes.ts:21` |
| GET | `/api/v1/payouts` | store, courier |  | `payouts/payouts.routes.ts:27` |

## Admin (35)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/admin/comments/reported` | admin |  | `drops/social.ts:235` |
| POST | `/api/v1/admin/comments/:commentId` | admin |  | `drops/social.ts:241` |
| GET | `/api/v1/admin/reviews/reported` | admin |  | `me/safety.ts:135` |
| POST | `/api/v1/admin/reviews/:id/resolve` | admin |  | `me/safety.ts:141` |
| GET | `/api/v1/admin/support` | admin |  | `support/support.routes.ts:56` |
| PATCH | `/api/v1/admin/support/:id` | admin |  | `support/support.routes.ts:64` |
| GET | `/api/v1/admin/stats` | admin |  | `admin/admin.routes.ts:21` |
| GET | `/api/v1/admin/system` | admin |  | `admin/admin.routes.ts:22` |
| GET | `/api/v1/admin/launch-demand` | admin |  | `admin/admin.routes.ts:23` |
| GET | `/api/v1/admin/users` | admin |  | `admin/admin.routes.ts:24` |
| DELETE | `/api/v1/admin/users/:id` | admin |  | `admin/admin.routes.ts:25` |
| GET | `/api/v1/admin/vendors` | admin |  | `admin/admin.routes.ts:26` |
| PATCH | `/api/v1/admin/vendors/:id/approve` | admin |  | `admin/admin.routes.ts:27` |
| DELETE | `/api/v1/admin/vendors/:id` | admin |  | `admin/admin.routes.ts:28` |
| PATCH | `/api/v1/admin/vendors/:id/commission` | admin | 0–50 %, new orders only, audited | `admin/admin.routes.ts:29` |
| GET | `/api/v1/admin/vendors/:id/commission-history` | admin |  | `admin/admin.routes.ts:30` |
| GET | `/api/v1/admin/couriers` | admin |  | `admin/admin.routes.ts:31` |
| PATCH | `/api/v1/admin/couriers/:id/approve` | admin |  | `admin/admin.routes.ts:32` |
| PATCH | `/api/v1/admin/couriers/:id/suspend` | admin |  | `admin/admin.routes.ts:33` |
| GET | `/api/v1/admin/orders` | admin |  | `admin/admin.routes.ts:34` |
| GET | `/api/v1/admin/analytics` | admin | ?from=YYYY-MM-DD&to=YYYY-MM-DD (Finnish days; default last 28) | `admin/admin.routes.ts:35` |
| GET | `/api/v1/admin/dac7` | admin | TIN decrypted here only | `admin/admin.routes.ts:36` |
| GET | `/api/v1/admin/dac7.csv` | admin |  | `admin/admin.routes.ts:37` |
| GET | `/api/v1/admin/stores/:id/statements` | admin | ?month=YYYY-MM | `admin/admin.routes.ts:38` |
| GET | `/api/v1/admin/drops` | admin |  | `admin/moderation.routes.ts:12` |
| PATCH | `/api/v1/admin/drops/:id` | admin |  | `admin/moderation.routes.ts:21` |
| GET | `/api/v1/admin/reports` | admin |  | `admin/moderation.routes.ts:29` |
| PATCH | `/api/v1/admin/reports/:id` | admin |  | `admin/moderation.routes.ts:36` |
| GET | `/api/v1/admin/payouts` | admin |  | `admin/moderation.routes.ts:44` |
| POST | `/api/v1/admin/payouts/:id/retry` | admin |  | `admin/moderation.routes.ts:51` |
| GET | `/api/v1/admin/reviews` | admin |  | `admin/moderation.routes.ts:57` |
| PATCH | `/api/v1/admin/reviews/:id` | admin |  | `admin/moderation.routes.ts:72` |
| GET | `/api/v1/admin/promo-codes` | admin |  | `promos/promos.routes.ts:33` |
| POST | `/api/v1/admin/promo-codes` | admin |  | `promos/promos.routes.ts:39` |
| PATCH | `/api/v1/admin/promo-codes/:id` | admin |  | `promos/promos.routes.ts:47` |

## Webhooks, redirects and health (6)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/payouts/return` | public | Stripe onboarding return page | `payouts/payouts.routes.ts:41` |
| GET | `/api/v1/payouts/refresh` | public | Stripe onboarding refresh page | `payouts/payouts.routes.ts:44` |
| POST | `/api/v1/payments/webhook` | public | Stripe signature checked, raw body; the only place an order becomes paid | `payments/payments.routes.ts:15` |
| POST | `/api/v1/media/cloudinary/notify` | public | Cloudinary signature checked, raw body | `media/media.routes.ts:19` |
| GET | `/health` | public | liveness | `index.ts:86` |
| GET | `/health/ready` | public | database check | `index.ts:87` |

## Public web pages (share, legal, App Links, signed links) (6)

| Method | Path | Auth | Note | Source |
|---|---|---|---|---|
| GET | `/api/v1/stores/statements/:storeId/:month.html` | public | no token: HMAC-signed 10-minute link | `sellers/sellers.routes.ts:53` |
| GET | `/d/:id` | public | public Drop share page | `drops/drops.routes.ts:138` |
| GET | `/.well-known/assetlinks.json` | public | Android App Links | `share/share.routes.ts:19` |
| GET | `/s/:storeId` | public | public store share page | `share/share.routes.ts:64` |
| GET | `/r/:code` | public | invite page | `share/share.routes.ts:96` |
| GET | `/legal/:doc` | public | privacy, terms, sellers, couriers | `legal/legal.routes.ts:125` |

