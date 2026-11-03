# Record of processing activities (GDPR Art. 30)

Status: API 2.16.1, 31 October 2026 (the code fixes C1–C5 and C7–C10 of `data-transparency-report.md` are in; C6 is a documented TODO). Written by the engineering side from the code (`backend/prisma/schema.prisma`, `backend/src`, the three apps read-only); **not legal advice**. Every retention period below is what the code does today; where the code and the intended period differ, the entry says so and `data-transparency-report.md` lists the fix. Open questions for the lawyer are marked **[LAWYER]**.

## Controller

| | |
|---|---|
| Controller | [COMPANY LEGAL NAME], Y-tunnus [Y-TUNNUS], [STREET ADDRESS], [POSTCODE] [CITY], Finland |
| Representative (Art. 27) | Not needed (established in the EU) |
| Data protection officer (Art. 37) | [DPO NAME AND CONTACT, OR "not appointed" WITH THE REASONING] **[LAWYER]**: courier location tracking may be "regular and systematic monitoring" on a large scale once volumes grow |
| Privacy contact | https://malvoya-api-eu.onrender.com/contact (topic "Privacy (GDPR) request"); [PRIVACY MAILBOX] |
| Joint / separate controllers | Each store is a separate controller for the order data it receives (privacy policy §1). Stripe is an independent controller for KYC/AML and its fraud signals; Google for Google Sign-In; Apple for Sign in with Apple; the OpenStreetMap Foundation for requests the apps send it |

## Processors and recipients (used in the entries below)

| Key | Who | Role | Data location | Transfer safeguard (to verify) |
|---|---|---|---|---|
| RENDER | Render Services, Inc. | Processor: hosting, Postgres, logs, backups (PITR) | Frankfurt, DE (`render.yaml` region `frankfurt`) | Data at rest in the EU; remote support access from the US: SCCs or DPF **[verify Render DPA]** |
| STRIPE | Stripe Payments Europe Ltd (IE); Stripe, Inc. (US) | Processor for payments; independent controller for KYC/AML and fraud | IE / US | DPF (Stripe, Inc.) and SCCs in Stripe's DPA |
| CLOUDINARY | Cloudinary Ltd. | Processor: images, videos, audio, private delivery proofs | [CLOUDINARY ACCOUNT REGION] | DPF or SCCs **[verify; check whether an EU storage region is selectable]** |
| FIREBASE | Google Ireland Ltd / Google LLC | Processor: Firebase Auth (phone, Apple), FCM push, Crashlytics | EU / US | DPF + SCCs (Google Cloud DPA) |
| GOOGLE-SI | Google | Google Sign-In ID-token verification (`google-auth-library`) | US | Independent controller for the user's Google account |
| TWILIO | Twilio Inc. | Processor: SMS sign-in codes, SMS withdrawal acknowledgements (only if `TWILIO_*` set) | US | DPF / SCCs **[verify]** |
| SMTP | [EMAIL PROVIDER] | Processor: transactional and optional email (`SMTP_*`) | [REGION] | [SAFEGUARD] |
| MAILBOX | [MAILBOX PROVIDER] (e.g. team Gmail) | Processor: `SUPPORT_EMAIL` receives support and contact-form copies | [REGION] | [SAFEGUARD] |
| LIVEKIT | LiveKit, Inc. (Cloud) or self-hosted | Processor: live-shopping WebRTC media (only if `LIVEKIT_*` set; not recorded) | [LIVEKIT REGION] | SCCs **[verify DPF status and DPA]** |
| SENTRY | Functional Software, Inc. | Processor: server error reports (only if `SENTRY_DSN` set; PII scrubbed, `lib/sentry.ts`) | [EU or US region] | DPF / SCCs; EU region recommended (`docs/scaling/scaling-plan.md`) |
| REDIS | [REDIS PROVIDER] | Processor: rate-limit counters keyed by IP, session cache, queue (only if `REDIS_URL` set) | [REGION] | [SAFEGUARD] |
| ORS | HeiGIT gGmbH (OpenRouteService), Heidelberg | Processor: street routes for the customer's tracking map (only if `ORS_API_KEY` set): receives two coordinate pairs (start/end) and a vehicle profile, nothing else; the API keeps routes in memory only (≤ 10 min, courier-origin ≤ 1 min) | DE (EU) | None needed (EU) **[verify HeiGIT terms/DPA]** |
| OSMF | OpenStreetMap Foundation (UK) | Independent recipient: map tiles and Nominatim geocoding requested directly by the apps | UK | Adequacy decision (UK) |
| PRH | Patentti- ja rekisterihallitus | Public authority: business-ID lookup (only the ID is sent) | FI | n/a |
| VERO | Verohallinto | Public authority: DAC7 report recipient | FI (may exchange with other EU tax authorities) | Legal obligation |
| STORE | The store of an order | Separate controller | FI | n/a |
| COURIER | The assigned courier | Recipient acting under the courier agreement | FI | n/a |

Technical and organisational measures that apply to every activity ("TOM-BASE"): TLS for all traffic (API, sockets, Stripe, Cloudinary, Firebase, OSM); hosting and database in the EU; Helmet security headers; strict CORS allow-list; Zod validation of every body; per-order authorisation in one function (`orders/access.ts#getOrderRelation`) for HTTP and sockets; JWT access tokens 15 min + single-use refresh tokens stored SHA-256-hashed; bcrypt (cost 12) passwords; session revocation (`tokensValidAfter`); global and per-route rate limits (`middleware/rateLimiter.ts`); request logs without IP, bodies or query strings, auth headers redacted (`index.ts` pino-http); Postgres statement timeouts; Render point-in-time recovery (3 days on Hobby, 7 days on Pro); CI with CodeQL, Dependabot and the `privacy-guard` job blocking remote fonts and analytics/session-replay scripts; `SECURITY.md` and `/.well-known/security.txt`. Admin: two-step sign-in required in production (`ADMIN_MFA_REQUIRED`), single ADMIN role (not split further), audit log (`AdminAuditLog`) for commission, legal publishing, recalls, catalogue admin, sounds, live ends, MFA events and (2.16.1) store/courier approvals, courier suspensions, bans and every DAC7 report view or CSV export.

---

## 1. Accounts and authentication

| | |
|---|---|
| Purpose | Create and secure accounts for shoppers, store owners, couriers and admins; sign-in by password, email code, Google, phone (Firebase), Apple; password reset; language of messages; age confirmation |
| Data subjects | Customers, store owners, couriers, admins |
| Data | `User`: name, email, phone, passwordHash (bcrypt), googleSub, appleSub, role, locale, ageConfirmedAt, termsAcceptedAt/termsVersion, isActive/deletedAt, tokensValidAfter, isMinor, emailMarketingOptOutAt; admin TOTP secret (AES-256-GCM) and hashed recovery codes; `RefreshToken` (SHA-256); `OtpCode` (target = email/phone in clear, SHA-256 code hash); `User.avatarUrl`, legacy `address/latitude/longitude` (never written by current code) |
| Legal basis | Art. 6(1)(b) contract; 6(1)(f) security of accounts; age confirmation 6(1)(b) (18+ terms) |
| Art. 9 | None |
| Recipients | FIREBASE (phone/Apple sign-in records, incl. phone number and IP), GOOGLE-SI, TWILIO (phone + code text), SMTP (email + code), RENDER |
| Transfers | FIREBASE, TWILIO, GOOGLE-SI (US): DPF/SCCs |
| Retention (code) | Account: until deletion (`auth.service.ts#deleteUserAccount` anonymises the row). Sign-in codes 10 min, reset codes 15 min, rows deleted hourly after expiry (`expired-sign-in-codes`). Refresh tokens 7 days; the presented token is deleted on logout; expired rows of every user are deleted hourly by `expired-sign-in-codes` (2.16.1, `services/privacyRetention.ts#purgeExpiredCredentials`) and a user's own at their next sign-in. Firebase Auth user deleted on account deletion (`accountCleanup.ts`, best effort) |
| TOMs | TOM-BASE; verified sign-ins never open `/register` accounts (409); attempt counters consumed before comparing codes; 5 wrong TOTP → 15-min lock; password-reset responses do not reveal accounts |

## 2. Orders, payments, refunds, returns and withdrawals

| | |
|---|---|
| Purpose | Conclude and perform sales; take payment through Stripe; refunds; returns and the 14-day withdrawal right incl. the withdrawal function (KSL 6:14 a); bookkeeping |
| Data subjects | Customers; store owners (as sellers) |
| Data | `Order` (items, prices, fees, tip, promo/referrer, paymentStatus, stripePaymentIntentId, timestamps, cancelReason/cancelledBy, deliveryAddress, deliveryLat/Lng, notes, scheduledStart/End, pickupCode (plain 6 digits)), `OrderItem`, `Return` (reason, conditionNote, storeNote, sealIntact, withdrawal, withdrawalAckSentAt/Channel), `ReturnItem`, `PromoRedemption`, `Rental` (feature off, 410), `StripeEvent` |
| Legal basis | 6(1)(b) contract; 6(1)(c) Accounting Act 1336/1997 2:10, Consumer Protection Act ch. 6 |
| Recipients | STORE (items, amounts, delivery address + pin + notes; **not** the customer's name, email or phone), COURIER (name, address, pin, notes after accepting; ~1 km area before), STRIPE (order id, user id, store id/name in metadata/description; card data via the SDK), SMTP/TWILIO (confirmations, withdrawal acknowledgements), RENDER |
| Transfers | STRIPE (US part): DPF/SCCs |
| Retention (code) | Orders, returns, redemptions: **no automated deletion**; kept until manually purged. The delivery pin (deliveryLat/Lng) and handover position are nulled 30 days after delivery/cancellation (`delivery-proof-purge`, 2.16.1). On account deletion: deliveryAddress, deliveryLat/Lng, notes, deliveryProblemNote and deliveredLat/Lng are nulled on the user's orders and `Return.conditionNote` on their returns (2.16.1); orders stay linked to the anonymised user. Intended: 6 years from the end of the financial year (privacy policy §7) → **purge/anonymisation job not built yet**; design in `data-transparency-report.md` §8 |
| TOMs | TOM-BASE; Stripe webhook signature check is the only place an order becomes paid; global Prisma `omit` hides pickupCode, referrerId, courierPay; pickup code shown only to the customer, 5 wrong tries lock 15 min; idempotency keys on money routes |

## 3. Delivery: dispatch, courier location, proof of delivery

| | |
|---|---|
| Purpose | Offer jobs to nearby approved couriers; show the courier's live position to the customer and store of the order; "courier arriving" notice; pay for the ride to the store; proof of delivery |
| Data subjects | Couriers; customers (delivery position, door photo) |
| Data | `Courier.latitude/longitude/locationAt` (latest position only, written at most every 15 s from sockets, every telemetry call over HTTP), live `courier:location` socket events (not stored), `Order.courierPay` (incl. approach distance), `Order.deliveredLat/Lng`, `deliveryProofPublicId` (Cloudinary `authenticated`), `handoverMethod`, `arrivingNotifiedAt`, `deliveryProblemReason/Note` |
| Legal basis | 6(1)(b) courier agreement and customer contract; 6(1)(f) proof of delivery and fraud prevention |
| Art. 9 | None intended; a door photo may incidentally show people or a home **[LAWYER]** |
| Recipients | Customer and store of the order (live position; since 2.17 also the computed street route courier → shop, `GET /orders/:id/route`, not stored), CLOUDINARY (photos), RENDER; ORS (route start/end points, only if configured); OSMF (map tiles requested by the apps) |
| Transfers | CLOUDINARY: DPF/SCCs |
| Retention (code) | Latest position: nulled on going offline (`POST /courier/status`), on admin suspension, ban and account deletion, and by the `courier-position-expiry` job (every minute, `privacyRetention.ts#expireStaleCourierPositions`) when no update arrived for `COURIER_POSITION_TTL_MINUTES` (default 15): idle couriers are also set offline; couriers carrying a job keep it and get `Courier.locationExpiredAt` (admin: position "none"). Positions older than 2 min are treated as unknown. Handover position (`deliveredLat/Lng`) and the delivery pin (`deliveryLat/Lng`): nulled 30 days after delivery/cancellation for every order by `delivery-proof-purge` (runs always; `privacyRetention.ts#purgeOldDeliveryLocations`); the photo is deleted by the same job only when Cloudinary is configured. Courier pay breakdown: with the order |
| TOMs | TOM-BASE; prominent disclosure before the Android permission prompt (`malvoya_courier/lib/core/location_disclosure.dart`), recorded as `Courier.locationDisclosureAt`; Android foreground-service notification while sharing; sharing stopped by `beforeLogout`; only the assigned courier can emit a location for an order (the socket re-checks the assignment every minute); signed, private delivery-photo URLs. Order payloads carry the courier's latitude/longitude only while the order is CONFIRMED/PROCESSING/SHIPPED with a courier assigned, and only to its customer and store (admins always): `orders.service.ts#withCourierPosition` (2.16.1) |
| DPIA | **Required in the lawyer's view? [LAWYER]**: systematic location monitoring of workers (EDPB/WP29 DPIA criteria: monitoring, employee-like relationship, location data). Recommend a DPIA before launch |

## 4. Order chat

| | |
|---|---|
| Purpose | Let customer and courier coordinate the handover |
| Data subjects | Customers, couriers, admins |
| Data | `OrderMessage` (orderId, senderRole, senderId, text ≤ 1000, createdAt) |
| Legal basis | 6(1)(b) |
| Recipients | Chat members (customer, assigned courier, admin); stores excluded |
| Transfers | None |
| Retention (code) | `chat-purge` every 6 h: deleted 30 days after `deliveredAt` or `cancelledAt`; the sender's own messages deleted at account deletion (messages of the other party stay until the purge). Orders that never get either timestamp keep their messages **[minor; check REFUNDED-only orders]** |
| TOMs | TOM-BASE; 30 messages/min; 409 once the order is closed; only members join `chat:<id>` |

## 5. Seller onboarding, trader information and business check

| | |
|---|---|
| Purpose | Approve sellers; show trader information (DSA Art. 30, Omnibus); verify the Y-tunnus in the free PRH/YTJ open data; product-safety self-certification; certificates |
| Data subjects | Store owners (business representatives and private sellers); persons named as manufacturer / EU responsible person / certificate holder |
| Data | `Store` (name, description, logo/banner, address, latitude/longitude, isHomeBased, phone, email, sellerType, businessId, openingHours, businessCheckStatus/RegisteredName/RegisteredAt/CheckedAt, readyForApprovalAt, safetyPledgeAt/Version), `EconomicOperator` (name, address, email, phone, url), `Certificate` (holderName, licenceNumber, evidenceUrl) |
| Legal basis | 6(1)(b); 6(1)(c) DSA Art. 30, GPSR Art. 19, Cosmetics Regulation; 6(1)(f) business check |
| Recipients | Public (store profile incl. exact address and coordinates, business ID; `stores.service.ts#publicStoreFields`), customers/couriers of an order (store phone), PRH (business ID only), CLOUDINARY, RENDER |
| Transfers | CLOUDINARY |
| Retention (code) | Until account deletion; then the Store row **stays** (name, address, coordinates, business ID, check result, description) as seller of past orders; phone/email nulled, products hidden, drops removed, Cloudinary folders deleted (`deleteStoreMedia`). No time limit on the remaining store row **[LAWYER: minimise after the bookkeeping period]** |
| TOMs | TOM-BASE; signed uploads to owner-scoped folders, `verifyOwnedUpload`; sellerType/businessId locked after verification; approval only by a person. **Note:** a home-based private seller's home address is public **[LAWYER]** |

## 6. DAC7 seller reporting

| | |
|---|---|
| Purpose | Collect and report seller data to Verohallinto (Council Directive (EU) 2021/514) |
| Data subjects | Store owners (business and private sellers) |
| Data | `StoreTaxInfo` (legalName, dateOfBirth, tinEncrypted, vatNumber, address, country), sales and consideration per quarter (derived), `Store.taxReminderAt/Count/Year` |
| Legal basis | 6(1)(c); henkilötunnus processing under Data Protection Act 1050/2018 §29 (processing laid down by law) **[LAWYER confirm]** |
| Art. 9 | None (the personal identity code is not Art. 9 data but a national identification number, Art. 87) |
| Recipients | VERO; admins only (decrypted in `/admin/dac7` and the CSV) |
| Transfers | None (VERO may exchange within the EU) |
| Retention (code) | Kept after account deletion; **no automated deletion** after the 10-year period (intended: 10 years from the end of the reporting year) |
| TOMs | AES-256-GCM with row-bound AAD (`lib/fieldCrypto.ts`, `DATA_ENCRYPTION_KEY`); TIN masked to the owner; formula-safe CSV; every report view and CSV export audited (`dac7.view` / `dac7.export`, 2.16.1). Deletion after 10 years: not automated yet (TODO job design in `data-transparency-report.md` §8) |

## 7. Payouts and statements (stores and couriers)

| | |
|---|---|
| Purpose | Pay stores and couriers through Stripe Connect Express; monthly statements |
| Data subjects | Store owners, couriers |
| Data | `Store/Courier.stripeAccountId`, `payoutsEnabled`; `Payout` (amount, status, releaseAt, stripeTransferId, failureReason, paidAt); statement rows (derived). Stripe receives email, country, business_type at account creation; bank/KYC data only on Stripe's pages |
| Legal basis | 6(1)(b); 6(1)(c) Accounting Act; AML (at Stripe) |
| Recipients | STRIPE |
| Transfers | STRIPE (US): DPF/SCCs |
| Retention (code) | No automated deletion (intended: with order records, 6 years) |
| TOMs | TOM-BASE; idempotency key per payout; statement links HMAC-SHA256, 10 min, constant-time compare |

## 8. Courier onboarding, pay calculation and transparency

| | |
|---|---|
| Purpose | Onboard couriers (vehicle, location disclosure), approval by a person, transparent pay (Platform Work Directive), ratings |
| Data subjects | Couriers |
| Data | `Courier` (name, phone, email, isApproved, vehicleType, locationDisclosureAt, readyForApprovalAt, rating/totalRatings), `Order.courierPay` breakdown, `Review.courierRating` (not public), delivery-problem reports |
| Legal basis | 6(1)(b); 6(1)(c) Platform Work Directive (from Dec 2026) |
| Recipients | Admins; customers and stores see the courier's name during a delivery |
| Transfers | None |
| Retention (code) | Courier row anonymised on deletion ("Deleted courier", phone/email/position nulled; vehicleType, rating, stripeAccountId stay). Job history with the orders |
| TOMs | TOM-BASE; no automatic assignment (first courier to accept), human approval, `/orders/available` explanation texts. The data export includes the courier's jobs (pay breakdown, rating, no customer data) and payouts (2.16.1). **Gap:** the courier app has no export button (Help sends the file) |

## 9. Drops, social features and feed ranking

| | |
|---|---|
| Purpose | Shoppable videos/photos; likes, saves, "Not interested", follows, comments, view counts; non-profiling ranking (DSA Art. 27) |
| Data subjects | Customers (viewers), store owners (publishers) |
| Data | `Drop`, `DropLike`, `DropSave`, `DropHide`, `DropView` (viewerKey `u:<userId>`, or `i:` SHA-256 of IP+day; `d:` install-id hashes from old builds are no longer written since 2.16.1; day; completed), `DropComment`, `StoreFollow`, `Favorite`, `Sound` (admin-curated) |
| Legal basis | 6(1)(b); 6(1)(f) counting views and ranking |
| Recipients | Public: comments with first name, counts only for likes/views/saves/followers; CLOUDINARY; RENDER |
| Transfers | CLOUDINARY |
| Retention (code) | Likes/saves/hides/follows/favourites/comments: until removed or account deletion. `DropView`: rows older than yesterday (UTC) deleted daily by `drop-view-purge` (2 days; the totals are denormalised on `Drop`); a user's `u:<id>` rows deleted at account deletion and included in the export (2.16.1) |
| TOMs | TOM-BASE; comments ≤ 300 chars, 20/10 min; hidden after 3 reports; `lib/minors.ts#mayPersonalise` guard |

## 10. Live shopping

| | |
|---|---|
| Purpose | Stores stream live video; signed-in viewers chat and send hearts; moderation |
| Data subjects | Store owners (camera/microphone), viewers |
| Data | `LiveStream`, `LiveMessage` (text ≤ 200, hidden), `LiveBan`, `LiveReport`; LiveKit tokens carry `u-<id>` and first name (guests random), WebRTC exposes IP to LiveKit; media not recorded |
| Legal basis | 6(1)(b); 6(1)(f) moderation |
| Recipients | Viewers (messages with first name), store, admins, LIVEKIT |
| Transfers | LIVEKIT: SCCs **[verify region and DPA]** |
| Retention (code) | `live-chat-purge` every 6 h: messages and mutes deleted 30 days after the live ended; deleted with the account. LiveReport and LiveStream rows: no limit |
| TOMs | TOM-BASE; tokens ≤ 6 h, HS256; chat 10/min; watchdog ends lives without heartbeat |

## 11. Reviews and ratings

| | |
|---|---|
| Purpose | Verified reviews (Omnibus); store and courier ratings |
| Data subjects | Customers (authors), store owners, couriers (rated) |
| Data | `Review` (storeRating, courierRating, comment, isHidden), `ReviewReport` |
| Legal basis | 6(1)(b); 6(1)(f) |
| Recipients | Public (store rating, comment, first name); courier rating not public |
| Retention (code) | Comment nulled at account deletion; ratings kept linked to the anonymised user (no limit) |
| TOMs | Only delivered orders, once, within 30 days; human moderation of reports |

## 12. Notice and action, moderation, blocks, IP notices

| | |
|---|---|
| Purpose | DSA Art. 16/17/20 notices and statements of reasons; GPSR product-safety notices; copyright/trademark notices; user blocks |
| Data subjects | Reporters (signed in or not), reported users/stores, rights holders |
| Data | `ProductReport` (reporterId, reporterEmail, details, ipNotice {name, email, work, location, onBehalfOf, goodFaith, at}), `DropReport`, `DropCommentReport`, `LiveReport`, `ReviewReport`, `UserBlock` |
| Legal basis | 6(1)(c) DSA, GPSR; 6(1)(f) blocks |
| Recipients | Admins; the store learns the reason, not the notifier's identity (unless consent/law) |
| Retention (code) | Reports kept as decision records (no limit); on the reporter's account deletion: name/email/onBehalfOf removed from ipNotice, ProductReport reporterId/email nulled, ReviewReports deleted; DropReport/LiveReport `reporterId` stays (pseudonymous). Blocks: until removed or deletion |
| TOMs | TOM-BASE; product reports 5/h; admin-only queues |

## 13. Product safety recalls

| | |
|---|---|
| Purpose | Lock recalled listings and notify every buyer directly (GPSR Art. 22(12), 35–37) |
| Data subjects | Customers who bought the product |
| Data | `Recall`, `RecallProduct`, `RecallNotification` (userId, channel, delivered, locale, sentAt) |
| Legal basis | 6(1)(c) |
| Recipients | FIREBASE (push), SMTP (email) |
| Retention (code) | No limit; kept linked to the anonymised user after deletion **[LAWYER: define the product-safety record period]** |
| TOMs | TOM-BASE; audited `recall.create/status` |

## 14. Notifications (push, email, SMS), launch alerts and email preferences

| | |
|---|---|
| Purpose | Service notifications; follower pushes; one-time launch alert; optional emails with unsubscribe |
| Data subjects | All users |
| Data | `DeviceToken` (FCM token, platform), `LaunchAlert` (latitude, longitude, area, notifiedAt), `User.emailMarketingOptOutAt`, `User.locale` |
| Legal basis | 6(1)(b) service messages; launch alert and optional email: 6(1)(a) consent **[LAWYER confirm]**, 917/2014 §200 |
| Recipients | FIREBASE (FCM), SMTP, TWILIO |
| Transfers | FIREBASE, TWILIO: DPF/SCCs |
| Retention (code) | Device token: deleted at sign-out (`DELETE /me/devices`), pruned when FCM reports it dead, max 10 per user, deleted at account deletion. Launch alert: until cancelled or account deletion (kept after `notifiedAt`). Opt-out timestamp: account life |
| TOMs | Unsubscribe token HMAC (`lib/unsubscribe.ts`), RFC 8058 one-click; GET changes nothing |

## 15. Customer support and contact form

| | |
|---|---|
| Purpose | Answer questions, privacy/withdrawal/DSA requests; DSA point of contact |
| Data subjects | Users and non-users |
| Data | `SupportRequest` (userId?, email, app, topic, message, orderId, status) |
| Legal basis | 6(1)(b), 6(1)(f); 6(1)(c) for GDPR/withdrawal/DSA requests |
| Recipients | Admins; MAILBOX (copy to `SUPPORT_EMAIL`); SMTP (acknowledgement) |
| Retention (code) | In-app requests deleted at account deletion; requests without an account (userId null: the contact form, or an app before sign-in) deleted 24 months after `updatedAt` by `contact-message-retention` (daily, 2.16.1); copies in the team mailbox must be deleted by hand on the same schedule (operational step) |
| TOMs | Contact form 8/h per IP, no scripts, strict CSP; support limiter |

## 16. Legal versions, acceptance records, age confirmation

| | |
|---|---|
| Purpose | Prove which contract version applies and that it was accepted; send copies; announce changes |
| Data subjects | All users |
| Data | `AgreementAcceptance` (doc, version, acceptedAt, ip truncated /24 or /48, userAgent ≤ 200, appVersion, method), `LegalVersion`, `User.ageConfirmedAt` |
| Legal basis | 6(1)(b); 6(1)(f) proof of contract |
| Recipients | SMTP (copies) |
| Retention (code) | `agreement-retention` daily: deleted when the user's `deletedAt` is older than 10 years. Active accounts: kept for the account's life |
| TOMs | Truncated IP; copy links signed, 10 min |

## 17. Referrals and promo codes

| | |
|---|---|
| Purpose | Invite discounts and rewards (off while `REFERRAL_DISCOUNT_CENTS` = 0) |
| Data subjects | Customers |
| Data | `User.referralCode`, `Referral` (referrerId, refereeId, orderId, rewardedAt), personal `PromoCode.userId`, `Order.referrerId` (omitted from every order query) |
| Legal basis | 6(1)(b) |
| Recipients | None outside Malvoya |
| Retention (code) | With orders; code cleared and personal codes switched off at account deletion |
| TOMs | Referrer hidden from stores and couriers |

## 18. Security, logging, error and crash reporting, backups

| | |
|---|---|
| Purpose | Keep the service secure and working; investigate faults and abuse |
| Data subjects | All users and visitors |
| Data | Request logs (request id, method, path without query, status, time); rate-limit counters keyed by IP (memory or REDIS, ≤ 1 h); `AdminAuditLog`; Sentry events (user id only, scrubbed) if enabled; Crashlytics reports (error, stack, app version, role, device model/OS/memory, installation id, numeric user id) from release builds; database backups |
| Legal basis | 6(1)(f) |
| Recipients | RENDER, SENTRY, FIREBASE (Crashlytics), REDIS |
| Transfers | SENTRY, FIREBASE: DPF/SCCs |
| Retention (code) | Request logs: [RENDER LOG RETENTION OF THE PLAN]; Crashlytics 90 days (Firebase default); Sentry per its plan [SENTRY RETENTION]; audit log: no limit; backups: PITR 3 or 7 days |
| TOMs | Scrubbing in `lib/sentry.ts` and `packages/malvoya_core/lib/src/crash/crash_scrubber.dart`; `sendDefaultPii: false`; no in-app opt-out for Crashlytics (objection by contact form) |

## 19. Data subject requests (export and deletion)

| | |
|---|---|
| Purpose | Art. 15/20 export, Art. 17 erasure, other requests |
| Data subjects | All users |
| Data | Export (`GET /auth/me/data`, `auth.service.ts#exportUserData`): user (incl. appleSub, isMinor), acceptances, blocks, orders, rentals, returns, store (products, drops, lives, tax info without TIN) and store payouts, courier profile (vehicle, disclosure, payout account, stored position) with jobs (pay breakdown, rating; no customer data) and payouts, favourites, likes, saves, hides, drop views, reviews, devices, comments, follows, launch alert, referrals, personal promos, support requests, chat messages sent, product/drop/comment/review/live reports made, recall notices, live messages |
| Legal basis | 6(1)(c) GDPR obligations |
| Retention (code) | Export generated on request, not stored. Deletion anonymises (see each entry) and cleans Firebase Auth and store media at Cloudinary (best effort, logged) |
| TOMs | Deletion refused while orders are open (409); sessions revoked, sockets disconnected. Deletion also blanks the user's return notes, the courier's delivery-problem note and the handover positions of their orders and deletes their drop views (2.16.1). **Gap:** store and courier apps have no export button (Help sends the file) |

## 20. Minors

| | |
|---|---|
| Purpose | DSA Art. 28: never personalise for known or likely minors |
| Data | `User.isMinor` (admin flag) |
| Legal basis | 6(1)(c) |
| Retention | Account life |
| TOMs | `lib/minors.ts#mayPersonalise`; no personalised ranking exists today |

---

Maintained next to `legal/privacy_policy.md`, `legal/data_explained.md` and `docs/compliance/data-transparency-report.md`. Update it whenever a model, processor or retention job changes.
