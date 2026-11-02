# Data transparency report

Status: audited on API 2.16.0, 31 October 2026; the code fixes are in API 2.16.1 (§7), the long-term retention job design in §8. Engineering view, derived from the code, **not legal advice**. Companion documents: `docs/compliance/records-of-processing.md` (GDPR Art. 30 record), `legal/data_explained.md` (served at `/legal/data-explained` and `/legal/tietosi`), `legal/privacy_policy.md`.

## 1. What was produced in this pass

| File | What |
|---|---|
| `docs/compliance/records-of-processing.md` | Art. 30 record: 20 processing activities with purpose, subjects, data, legal basis, recipients, transfers, retention from the code, TOMs |
| `legal/data_explained.md` | "Tietosi selkokielellä / Your data, explained": Finnish first, then English; by role (shoppers, shops, couriers, everyone), each item with the eight questions; never-do list, location, payments, security, rights, processors |
| `backend/src/modules/legal/legal.routes.ts` | New page `data-explained` (file `data_explained.md`), aliases `tietosi` and `your-data`; it appears automatically in the navigation of every legal page |
| `backend/test/e2e/e2e.js` (+ README) | 2 checks: both URLs answer 200 with Finnish before English; terms and privacy pages list it, and the privacy text links to it (1033 → 1035 checks) |
| `legal/privacy_policy.md` | Corrections listed in §4 |
| `legal/account_deletion.md` | "What is kept" was incomplete (said nothing else is kept); in-app path corrected |
| `web/` | Legal view entry, footer link, help article `data` (FI `/apua/mita-tietoja-keraamme/`, EN `/en/help/what-data-we-collect/`), `LEGAL.dataExplained` in `site.ts`, README count |
| `docs/play-data-safety.md` | Two stale answers fixed: order chat is stored (30 days), the customer app reads GPS once on "Use my location" |

Verification: `npx tsc --noEmit` in `backend/` passes. `npm run build` in `web/` passes (31 pages, 1324 internal links, no broken links). The Markdown of `data_explained.md`, `privacy_policy.md` and `account_deletion.md` was rendered with the API's own `renderMarkdown` (no unrendered links, table rows consistent). **The e2e suite was not run**: Docker did not answer (`docker ps` hung), so the database and stripe-mock could not start.

## 2. Inventory

R = retention as the 2.16.0 code implemented it. ✱ = differed from the policy or had no automated limit (see §3); most are fixed in 2.16.1, see §7.

| Data | Model / source | Subjects | Who sees it | Where | R (code) |
|---|---|---|---|---|---|
| Name, email, phone, password hash, Google/Apple id, locale | `User` | all | user, admins; courier sees customer name | Render FRA; Firebase for phone/Apple sign-in | until deletion (anonymised) |
| Age confirmation | `User.ageConfirmedAt` | all | admins | Render | account life |
| Minor flag | `User.isMinor` | customers | admins | Render | account life |
| Optional-email opt-out | `User.emailMarketingOptOutAt` | all | admins | Render | account life |
| Admin TOTP secret, recovery codes | `User.totp*` | admins | nobody (encrypted/hashed) | Render | until disabled |
| Refresh tokens | `RefreshToken` (SHA-256) | all | nobody | Render | 7 days; expired rows removed only at the user's next sign-in ✱ |
| Sign-in/reset codes | `OtpCode` (hash; target in clear) | all | nobody | Render | 10 / 15 min, purged hourly |
| Delivery address, pin, notes | `Order.deliveryAddress/Lat/Lng/notes` | customers | store (no name), courier after accept, admins | Render | with the order; nulled at account deletion |
| Saved addresses | SharedPreferences (customer app) | customers | user | phone only | until removed |
| Orders, items, prices, payment status | `Order`, `OrderItem`, `PromoRedemption` | customers, stores | parties of the order, admins; Stripe metadata (order id, user id, store) | Render, Stripe | **no deletion job** ✱ (intended 6 y) |
| Returns, withdrawals, acknowledgements | `Return`, `ReturnItem` | customers | customer, store, admins | Render | as orders ✱; `conditionNote` not cleared at deletion ✱ |
| Pickup code | `Order.pickupCode` (plain) | customers | customer only | Render | with the order |
| Card / wallet data | Stripe SDK | customers | Stripe | Stripe | Stripe's rules |
| Courier live position | `Courier.latitude/longitude/locationAt` | couriers | customer + store of the active order; **also returned on past orders** ✱ | Render | nulled on going offline; stale positions never cleared if the app dies ✱ |
| Courier live stream | socket `courier:location` | couriers | order room | not stored | — |
| Handover position | `Order.deliveredLat/Lng` | couriers, customers | customer, courier, admins | Render | 30 days **only for photo deliveries with Cloudinary on; IN_PERSON kept forever** ✱ |
| Delivery photo | Cloudinary `authenticated`, `Order.deliveryProofPublicId` | customers | customer, courier, admins (signed URL) | Cloudinary | 30 days (`delivery-proof-purge`) |
| Courier pay breakdown, job history | `Order.courierPay`, `courierFeeCents` | couriers | courier, admins | Render | with orders ✱; not in export ✱ |
| Courier vehicle, disclosure ack | `Courier.vehicleType/locationDisclosureAt` | couriers | admins | Render | kept after deletion |
| Courier rating | `Review.courierRating`, `Courier.rating` | couriers | courier (average), admins | Render | no limit |
| Order chat | `OrderMessage` | customers, couriers | members, admins | Render | 30 days after delivery/cancellation; sender's messages at deletion |
| Store profile (public) | `Store` | store owners | public incl. exact address + coordinates of home-based stores ✱ | Render, Cloudinary | row kept after deletion (phone/email nulled) ✱ |
| Business check result | `Store.businessCheck*` | business sellers | admins | Render; PRH gets the ID | kept with the store row (policy said "deleted with the store") ✱ |
| DAC7 tax data | `StoreTaxInfo` (TIN AES-256-GCM) | sellers | owner (masked), admins, Verohallinto | Render | kept after deletion; **no 10-year deletion job** ✱ |
| Payouts, Stripe account ids | `Payout`, `stripeAccountId` | stores, couriers | owner, admins, Stripe | Render, Stripe | no deletion job ✱; not in export ✱ |
| Economic operators, certificates | `EconomicOperator`, `Certificate` | third persons named by sellers | public / admins | Render, Cloudinary | until removed |
| Products, photos, videos, drops, sounds | `Product`, `ProductVideo`, `Drop`, `Sound` | store owners | public | Render, Cloudinary | until removed; Cloudinary folders deleted at deletion |
| Likes, saves, hides, follows, favourites | `DropLike`, `DropSave`, `DropHide`, `StoreFollow`, `Favorite` | customers | counts only | Render | until removed / deletion |
| Drop views | `DropView` (`u:<id>` / hashed IP+day / hashed install id) | viewers | nobody (counts) | Render | **no limit, not deleted at account deletion, not exported** ✱ |
| Drop comments | `DropComment` | customers | public (first name) | Render | until removed / deletion |
| Live chat, mutes | `LiveMessage`, `LiveBan` | viewers | viewers (first name), store, admins | Render; LiveKit sees id, first name, IP | 30 days after the live (`live-chat-purge`) |
| Live streams, reports | `LiveStream`, `LiveReport` | stores, reporters | admins | Render | no limit |
| Reviews | `Review` | customers | public (first name) | Render | comment nulled at deletion; ratings kept |
| Reports, IP notices | `ProductReport`, `DropReport`, `DropCommentReport`, `ReviewReport` | reporters, rights holders | admins | Render | decision records, no limit; identity stripped at deletion |
| Blocks | `UserBlock` | users | blocker | Render | until removed / deletion |
| Recall notices | `RecallNotification` | buyers | admins | Render | no limit ✱ |
| Push tokens | `DeviceToken` | all | nobody | Render, FCM | sign-out, dead-token pruning, max 10 per user |
| Launch alert | `LaunchAlert` (lat, lng, area) | customers | admins (summary) | Render | until cancelled / deletion |
| Referrals, personal promos | `Referral`, `PromoCode.userId`, `Order.referrerId` | customers | admins | Render | with orders |
| Support, contact form | `SupportRequest` | users, visitors | admins, team mailbox | Render, [MAILBOX PROVIDER] | in-app: until deletion; **contact form: no limit** ✱ |
| Acceptance records | `AgreementAcceptance` (IP /24 or /48, UA, app version) | all | user, admins | Render | account life + 10 y (`agreement-retention`) |
| Request logs, request ids | pino-http | all | developers | Render | [Render plan] ✱ placeholder |
| Rate-limit counters (IP) | memory / Redis | all | nobody | memory or Redis | ≤ 1 h |
| Error reports | Sentry (if `SENTRY_DSN`) | all | developers | Sentry | [plan] |
| Crash reports | Firebase Crashlytics (release builds) | app users | developers, Google | Firebase | 90 days; no in-app opt-out ✱ |
| Admin audit log | `AdminAuditLog` | admins, affected entities | admins | Render | no limit; DAC7 decryption, bans, approvals not audited ✱ |
| Map tiles, geocoding | OSM tile servers, Nominatim (from the phone) | app users | OSMF | UK | OSMF's policy |
| Backups | Render PITR | all | Render | Frankfurt | 3 days (Hobby) / 7 days (Pro) |

Not present in the code (checked): no telemetry or position history table (removed in Sep 2026), no Stripe Customer objects, no identity documents (KYC is on Stripe's pages), no analytics SDK, no ads SDK, no session replay, no Twilio number masking, no saved addresses on the server (`User.address/latitude/longitude` exist but are never written).

## 3. Mismatches between the code and the privacy policy

### Fixed in the privacy policy (text was wrong or incomplete)

| # | What the policy said | What the code does | Change |
|---|---|---|---|
| 1 | §5: the store gets "your name, the items ordered and the delivery address" | Stores get items, delivery address, pin and notes; **no** name, email or phone (`order:new`, `orderDetailInclude`). Couriers get the customer's name (`listCourierOrders` `user.name`) | §5 rewritten: store vs courier vs customer vs public |
| 2 | Live shopping not mentioned | `LiveStream/LiveMessage/LiveBan/LiveReport`, LiveKit receives `u-<id>`, first name, IP; chat purged 30 days after the live | §2 row, §5 processor, §6 transfer, §7 retention |
| 3 | Drop saves, "Not interested", follows, comments, launch alert, referrals, support requests not covered | All exist (2.8–2.14) | §2 rows; §7 rows |
| 4 | OpenStreetMap not named | Customer, store and courier apps load OSM tiles; customer and store apps call Nominatim from the phone | §3 and §5 (independent recipient), §6 (UK adequacy) |
| 5 | §3 customers: only "coordinates you enter" | Customer app reads GPS once on "Use my location" (`core/current_position.dart`); store app once in store setup | §3 rewritten |
| 6 | §3 couriers: only the latest position is kept | Also the handover position (30 days) and the approach distance in `courierPay` | §3 |
| 7 | Technical logs contain the IP address | Request logs hold id, method, path without query, status; no IP. IP only in the rate limiter (≤ 1 h). Sentry optional, scrubbed | §2 row |
| 8 | Drop views: signed-out = daily IP hash only | API still accepts `installId` from old builds (stored as SHA-256) | §2 row mentions it; §7 retention "kept with the drop" |
| 9 | Business check results "deleted with the store" | The store row is never deleted; result stays | §7 row; new row on the store record after deletion |
| 10 | Rights §8: "Profile → Privacy → Download my data" for everyone | Only the customer app has the button; store/courier apps have none; email/phone can be changed only via support | §8 rewritten; consent withdrawal added |
| 11 | Security §9: four lines | Also AES-256-GCM, signed links, rate limits, admin two-step, audit log, backups | §9 extended (pickup codes are **not** hashed, so they are not described as hashed) |
| 12 | Payments: no mention of what Stripe receives or of the SDK's fraud data | Stripe gets order id, user id, store name; SDK collects device data | §2 row |
| 13 | Missing: courier job/pay/rating data, public store profile incl. home address, product-safety contacts | All exist | §2 rows |
| 14 | Retention gaps: reviews, support, live chat, follows, launch alert, payouts, backups, refresh-token cleanup | See §2 inventory | §7 rows (with placeholders where no period exists in code) |
| 15 | `account_deletion.md`: "Apart from short-lived security logs, nothing else is kept" | Acceptance records (10 y), store record, reports, backups are kept | "What is kept" extended |

### Code does not match the policy: code fixes needed before publishing (main session, backend)

These are **publication blockers** for `data_explained.md` and the policy, which describe the intended behaviour:

| # | Problem | Where | Suggested fix |
|---|---|---|---|
| C1 | Handover position kept forever for IN_PERSON deliveries (purge selects only orders with a photo, and only when Cloudinary is configured) | `orders.service.ts#purgeOldDeliveryProofs`, `scheduler.ts` (`enabled: mediaConfigured`) | Second step nulling `deliveredLat/Lng` where `deliveredAt < now − 30 d`; run the job regardless of Cloudinary |
| C2 | Courier's live position returned on every order, including past ones (customer order detail, store order list) | `orders.service.ts` `courierPublic` in `orderDetailInclude` and the VENDOR branch of `listOrdersFor` | Include `latitude/longitude` only while status is CONFIRMED/PROCESSING/SHIPPED and the courier is assigned |
| C3 | Stale courier position never cleared if the app dies without going offline | no job | Scheduler job: null `latitude/longitude/locationAt` where `locationAt < now − 15 min` (positions > 2 min count as unknown anyway) |
| C4 | `DropView` rows: no retention, not deleted with the account, not exported | `drops.service.ts`, `auth.service.ts` | Delete `u:<id>` rows at deletion; purge rows older than e.g. 90 days (counts are denormalised on `Drop`); stop accepting `installId` |
| C5 | Contact-form `SupportRequest` rows (userId null) kept forever | `support/contactPage.ts` | Retention job (period from the lawyer) |
| C6 | No automated deletion for orders/payouts after 6 years and DAC7 data after 10 years | — | Yearly job, or a documented manual procedure |
| C7 | Data export misses courier jobs and pay, payouts, `appleSub`, `isMinor`, courier vehicle/disclosure, reports made (drop/comment/review/live), recall notices; store/courier apps have no button | `auth.service.ts#exportUserData`; apps | Extend the export; add "Download my data" to the store and courier apps |
| C8 | Return `conditionNote` and order `deliveryProblemNote` stay after account deletion | `deleteUserAccount` | Null them (or justify keeping them as order records) |
| C9 | Expired refresh tokens of inactive users never removed | `session.ts` | Add to the `expired-sign-in-codes` job |
| C10 | DAC7 report access (TIN decryption), bans and approvals not in the audit log | `admin/dac7`, `admin.controller.ts` | Audit `dac7.view/export`, `user.ban`, `store.approve`, `courier.approve` |

## 4. Every change made to `legal/privacy_policy.md`

1. §1: plain-language link to `/legal/data-explained`.
2. §2 payment row: what Stripe receives; Stripe SDK device data.
3. §2 courier location row: "online or delivering".
4. §2 new rows: courier jobs/pay/ratings; public store profile (incl. home address); product-safety contacts and certificates; comments; live shopping; launch alert (consent); invite codes; support and contact form.
5. §2 drops row: saves, "Not interested", follows; old install-id hashing.
6. §2 push row: follower news and launch alert; "No advertising" instead of "No marketing".
7. §2 technical logs row: no IP in logs; IP only for rate limiting; Sentry.
8. §3 rewritten: "Use my location", stores' one-time fix, couriers' stored items, OpenStreetMap.
9. §5: store / courier / customer / public recipients; processors LiveKit, Sentry, mailbox, Google Sign-In, Apple via Firebase, Crashlytics; OSMF as independent recipient.
10. §6: LiveKit, Sentry, Apple; OSMF and the UK adequacy decision.
11. §7 new/changed rows: drop views, likes/saves/follows, comments, live chat, launch alert, reviews, courier/payout records, support requests (placeholder), push tokens (max 10), codes (purged within an hour), business check, store record after deletion, refresh tokens, request logs (placeholder), backups.
12. §8: export path and store/courier gap; correction via Help; consent withdrawal; crash-report objection example.
13. §9: security measures that exist.

Note: the policy in force is the stored `LegalVersion` text, not the file. These changes reach `/legal/privacy` only when an admin publishes a new version (admin panel → Legal, summaries in both languages). `data_explained.md` is a plain file page and is live with the next deploy.

## 5. Open items for the lawyer

1. **DPIA for courier location tracking** (systematic monitoring of workers with location data), before launch. Also consider whether a DPO is needed once volumes grow.
2. **Transfer assessments (TIA)** and confirmation of each provider's mechanism: Stripe, Google/Firebase, Twilio, Cloudinary, LiveKit, Sentry, Render (US company, EU hosting), the email and mailbox providers, Redis if used. Check DPF certification on dataprivacyframework.gov; otherwise SCCs. Prefer EU regions (Cloudinary, LiveKit, Sentry).
3. **Processor agreements (DPAs) to sign/accept:** Render, Stripe, Cloudinary, Google Cloud/Firebase, Twilio, [EMAIL PROVIDER], [MAILBOX PROVIDER], LiveKit, Sentry, [REDIS PROVIDER].
4. **OpenStreetMap:** direct requests from phones share IP and searched addresses with OSMF (independent recipient); the Nominatim policy limits heavy use. Decide whether to proxy geocoding through the API or use a contracted geocoder.
5. **Home-based private sellers' public address** (exact coordinates): is publication proportionate for private persons, or should only an area be shown until an order?
6. **Store and courier access to past addresses:** stores keep delivery addresses and couriers keep customer names and addresses in their order lists without time limit. Consider limiting to e.g. 30 days after closure.
7. **Legal bases to confirm:** launch alert (consent vs contract); crash reports (legitimate interest without an in-app switch); henkilötunnus under Data Protection Act §29; acceptance records 10 years (Limitation of Debts Act).
8. **Retention periods to set:** contact-form messages, request logs (Render plan), Sentry, recall notification records, reports and audit log, store record after deletion, live-stream and report rows.
9. **Art. 9 incidental data:** delivery photos and drop/live media may show people; confirm the instructions to couriers and sellers are enough.
10. **Joint controllership:** the store-as-separate-controller model and the information duties stores take on.
11. **Age assurance:** self-declared 18+ tick box; confirm proportionality.
12. Review the Finnish wording of `data_explained.md` and fill the placeholders: [COMPANY LEGAL NAME], [Y-TUNNUS], [EMAIL PROVIDER], [MAILBOX PROVIDER], [CLOUDINARY REGION], [LIVEKIT REGION], [SENTRY REGION], [LOG RETENTION OF THE HOSTING PLAN], backup [7] days.

## 6. In-app links for the main session to add after the release build

The page URL: `https://malvoya-api-eu.onrender.com/legal/data-explained` (or `/legal/tietosi`). Each app already has `openLegal(doc)` from `malvoya_core` (`packages/malvoya_core/lib/src/platform/legal_links.dart`), so the call is `openLegal('data-explained')`.

| App | Screen (file) | Where | Wording (`tr(context, en, fi)`) |
|---|---|---|---|
| Malvoya (customer) | `Malvoya_customer/lib/screens/privacy_gdpr_screen.dart`, card "Tracking and consent", directly under "Read the full privacy policy" | New `ListTile`, icon `Icons.menu_book_outlined`, trailing `open_in_new` | Title: "Your data, explained" / "Tietosi selkokielellä"; subtitle: "What we collect, why, and how long we keep it" / "Mitä keräämme, miksi ja kuinka kauan säilytämme" |
| Malvoya (customer) | same screen, card "Your rights", under "Download your data" | Optional second entry | "Read what is in your download" / "Lue, mitä latauksesi sisältää" |
| Malvoya Store | `malvoya_vendor/lib/screens/agreements_screen.dart`, after the `openLegal('privacy')` tile (line ~169) | New tile | "Your data, explained" / "Tietosi selkokielellä"; subtitle "Shops: what we keep about you and your customers" / "Kaupoille: mitä säilytämme sinusta ja asiakkaistasi" |
| Malvoya Store | account sheet (`widgets/account_sheet.dart`), above "Delete account" | Tile | "Your data" / "Tietosi", opens the page; plus "Ask for a copy of your data" / "Pyydä kopio tiedoistasi" opening Support with topic "Account and privacy" until an export button exists |
| Malvoya Courier | `malvoya_courier/lib/core/location_disclosure.dart`, the disclosure dialog | `TextButton` under the text, before "Not now" | "How we use your location" / "Miten käytämme sijaintiasi" → `openLegal('data-explained')` |
| Malvoya Courier | `screens/help_screen.dart`, next to the courier-agreement button (line ~164) | Button | "Your data, explained" / "Tietosi selkokielellä" |
| Malvoya Courier | `screens/pending_approval.dart`, next to the agreement link (line ~145) | Text button | same wording |
| Admin panel | Legal page | Link | "Plain-language data page" → the URL |

After adding them: `flutter analyze --no-pub lib` in each app, and update `docs/play-data-safety.md` deletion/export notes if an export button is added to the store or courier app. Also update the e2e count in `CLAUDE.md` (1033 → 1035) and mention `/legal/data-explained` in its legal-pages line. (Done in 2.16.1.)

## 7. Code fixes in API 2.16.1 (status of C1–C10)

The §2 inventory and §3 table above describe 2.16.0 as audited. Since 2.16.1 the code matches `legal/data_explained.md` and `legal/privacy_policy.md` for every item below. The retention jobs live in `backend/src/services/privacyRetention.ts` and are scheduled in `services/scheduler.ts`. The e2e suite has 30 new checks for them (section "Privacy fixes from the data audit (2.16.1)").

| # | Status | What the code does now | Retention chosen and why |
|---|---|---|---|
| C1 | Fixed | `delivery-proof-purge` (every 6 h) **always runs**. `purgeOldDeliveryLocations` nulls `deliveredLat/Lng` (handover position) **and** `deliveryLat/Lng` (the customer's map pin) on every order delivered, cancelled or refunded more than 30 days ago, whatever the handover method (IN_PERSON, PHOTO, ADMIN). The photo at Cloudinary is deleted by the same job only when Cloudinary is configured. The written `deliveryAddress` stays with the order record. | **30 days**: what the texts already promised for the handover position. The pin is not needed once the order is closed (nothing reads it after delivery; the 14-day withdrawal period and return handling fit inside 30 days); the address text covers the bookkeeping record. Both texts now say the pin goes after 30 days. |
| C2 | Fixed | `orders.service.ts#withCourierPosition`: the courier's `latitude/longitude` are in an order payload only while the order is CONFIRMED/PROCESSING/SHIPPED **and** a courier is assigned (from acceptance until delivery, or until return to the shop, which cancels the order), and only for that order's customer and store; admins always. Everyone else (the courier's own order view, finished/cancelled/unassigned orders, the store's list of past orders) gets the courier's id and name with null coordinates. Rentals never carry the position. The socket relay re-checks the courier's assignment every minute, so a finished order stops relaying positions. | — |
| C3 | Fixed | Job `courier-position-expiry` (every minute): no position update for `COURIER_POSITION_TTL_MINUTES` (default **15**) → idle couriers are set offline and their position cleared (socket event `courier:status {isOnline:false, reason:"no_position"}`; telemetry then answers 409); couriers carrying an order/rental/return keep the job and its status, only the position is cleared and `Courier.locationExpiredAt` is set (migration `20261031090000_privacy_retention`); the next update clears the marker. Offline couriers never keep a position (ban and suspension now clear `locationAt` too). `GET /admin/couriers` and `GET /admin/orders` return `position {status: live/stale/none, reportedAt, clearedAt}` (never coordinates). | **15 minutes**, configurable: long enough for short GPS gaps (tunnels, a phone restart) during a delivery, short enough that a killed app does not leave a position behind. Positions older than 2 min already count as unknown for pay and arrival checks. |
| C4 | Fixed | `DropView` rows are deleted after 2 days (`drop-view-purge`, daily); a user's `u:<id>` rows are deleted at account deletion and are in the export (`dropViews`). The `installId` sent by old app builds is accepted (no 400) but **ignored**: signed-out views are keyed only by the daily IP hash, so no `d:` rows are written. | **2 days**: the rows only de-duplicate one view per viewer per day; the totals (`viewCount`, `completeCount`, `watchSeconds`) are denormalised on `Drop`. Keeping yesterday's row avoids edge effects around midnight UTC. |
| C5 | Fixed | `contact-message-retention` (daily) deletes `SupportRequest` rows without an account (`userId` null: the /contact form, or an app before sign-in) 24 months after their last change. In-app requests stay until account deletion. | **24 months** after the last update: covers follow-ups, withdrawal and DSA notices and the usual time to raise a complaint, without keeping non-users' messages indefinitely. **[LAWYER]** to confirm (3 years, the general limitation period, could be argued for withdrawal notices sent through the form). Copies in the team mailbox must be deleted by hand on the same schedule (operational step; the texts say "by hand"). |
| C6 | Open (documented) | See §8 for the job design. Orders, returns, payouts and DAC7 data are still kept without an automated end. | 6 years (Accounting Act 2:10) / 10 years (DAC7), as documented. |
| C7 | Fixed (API) | `GET /auth/me/data` also returns `appleSub`, `isMinor`, the courier profile (vehicle, disclosure, readiness, payout account id, stored position), `courierJobs` (order id, store, times, status, handover method, problem reason, `courierFeeCents`, tip, `courierPay` breakdown, the rating given; **no customer name, address or notes**), `courierPayouts`, `storePayouts`, `dropViews`, `dropReports`, `commentReports`, `reviewReports`, `liveReports`, `recallNotices`. | Still open: the store and courier apps have no "Download my data" button (an app change, not made here); the texts keep saying Help sends the file. |
| C8 | Fixed | Account deletion also nulls `Return.conditionNote` (the customer's note) on the user's returns and `deliveryProblemNote` and `deliveredLat/Lng` on their orders. Amounts, reasons and the store's own `storeNote` stay (the store's record of its decision). | — |
| C9 | Fixed | `expired-sign-in-codes` (hourly) also deletes expired refresh tokens of every user. | Within an hour of expiry (tokens live 7 days). |
| C10 | Fixed | Audited: `user.ban`, `store.approve`, `courier.approve`, `courier.suspend` and `dac7.view` / `dac7.export` (entity `Dac7Report`, entityId = the year) each time the report is opened or downloaded. | The audit log itself has no limit yet (§5 item 8). |

Test-only setting: `test/e2e/test.env` sets `COURIER_POSITION_TTL_MINUTES=600`, so the API's own job does not set the suite's couriers offline during a long run; the privacy checks run the job in the test process with the default and with 30.

## 8. TODO: long-term retention job (C6)

Not built in 2.16.1: the first deletion falls due in 2033 at the earliest (no real orders exist before launch) and the rules need the lawyer's sign-off. Design, to be built before the first financial year closes:

**Job `accounting-retention`** (scheduler, daily with a lease like the other jobs, or yearly in January).

1. **Cut-off.** Financial year = calendar year unless decided otherwise ([FINANCIAL YEAR]). An order is due when `createdAt < 1 January of (current year − 6)` (Accounting Act 2:10: 6 years from the end of the financial year). An order from 2026 is due on 1 January 2033.
2. **Orders and what hangs on them.** For due orders, in batches of 500, one transaction each: delete `ReturnItem`, `Return`, `PromoRedemption`, `Referral`, `Payout` (same cut-off on `Payout.createdAt`), `Review` (or keep the star rating without the user/order link if the store's average must not change: decision needed), `OrderItem`, then `Order`. Alternative if aggregates must stay: anonymise instead (link to an "archived" placeholder user; null `stripePaymentIntentId`, `pickupCode`, `courierPay`, notes and address fields).
3. **Rentals** (off since 2.13): the same rule on `Rental` / `RentalItem`.
4. **DAC7.** `StoreTaxInfo` is due 10 years after the end of the last year the seller was reportable: no orders with `deliveredAt` in the last 10 full years and `updatedAt` older than 10 years. Delete the row (the TIN is encrypted; deleting the row is enough). Log counts, never data.
5. **Stores of deleted accounts.** Once the last order (step 2) and the DAC7 row (step 4) are gone, delete the `Store` row with its products, operators, certificates and business-check result (the reason to keep it, being the seller on past orders, is gone).
6. **Couriers of deleted accounts.** Once their last order and payout are gone, delete the anonymised `Courier` row.
7. **Recall notices, reports, audit log, live stream rows:** add to the same job when the lawyer sets the periods (§5 item 8).
8. **Backups:** deleted rows leave Render's point-in-time backups within the backup period.
9. **Safety:** never touch an order with an open return, a failed payout or an unsettled refund; log counts only; `ACCOUNTING_RETENTION_DRY_RUN=true` by default until the lawyer signs off; e2e checks with back-dated rows as for the 2.16.1 jobs.

Until the job exists, a manual procedure each January is enough: run the queries of steps 2–6 as a dry run and delete what is due.
