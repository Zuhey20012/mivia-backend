# Google Play Data safety answers

One form per app: Play Console → app → **Policy and programs → App content → Data safety**.
These answers come from the code (checked 2026-10-15; crash reporting added 2026-10-30) and `legal/privacy_policy.md`. Where the two disagree, the list at the end says what to fix.

## Words Google uses (read this first)

- **Collected** = the data leaves the phone (to our API, or to an SDK's servers such as Stripe or Firebase). Data from SDKs inside our app counts as ours.
- **Shared** = sent to a *third party*. It is **not** sharing when it goes to a **service provider** that works for us (Stripe, Cloudinary, Firebase/Google, Render, Twilio, the email provider), when the law requires it, or when the user starts the transfer and expects it.
- **Processed ephemerally** = only held in memory, never stored. You still declare it, but Play does not show it.
- **Optional** = the user can use the app without giving it.

**Recommendation on "shared":** stores and couriers are independent of Malvoya (the privacy policy calls each store a separate controller). Passing a customer's name and address to the store is started by the customer (placing an order), so it can be left out. The courier's position going to a business (the store) is less clearly user-started. To keep the form and the privacy policy telling the same story, this guide marks those transfers as **shared, for App functionality**. Over-declaring costs little; under-declaring is a policy breach.

## Answers that are the same for all three apps

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes.** The API, sockets, Stripe, Cloudinary, Firebase and OpenStreetMap are all `https`/`wss`. No `http://` URL and no `usesCleartextTraffic` in the apps. |
| Which account creation methods does your app support? | Username/password **and** other authentication (Google sign-in, phone number with SMS code). Sign in with Apple exists in code but is for iOS. |
| Do you provide a way for users to request that their data is deleted? | **Yes** |
| Delete account URL | **Does not exist yet.** See "Web deletion page" below. It is required. |
| Data is sold? | No |
| Advertising or marketing purpose? | Never. No ads SDK, no `AD_ID`. |
| Independent security review / Families badge | No |

Service providers (not "sharing"): Stripe Payments Europe (payments, Stripe Connect payouts), Cloudinary (photos and videos), Google Firebase (sign-in, push, Crashlytics crash reports), Render (hosting, Frankfurt), Twilio (SMS codes), [EMAIL PROVIDER] (email).

### Crash logs and diagnostics (all three apps)

Every app includes Firebase Crashlytics (`firebase_crashlytics`, set up in `packages/malvoya_core/lib/src/crash/` and each app's `lib/main.dart`; owner steps in `docs/release/crashlytics.md`). Add these two rows to each app's form:

| Data type (Play name) | Collected | Shared | Ephemeral | Required / optional | Purposes | What it is in Malvoya |
|---|---|---|---|---|---|---|
| **App info and performance → Crash logs** | Yes | No (Google is a service provider) | No | Required | Analytics | Crash and error reports: error type, cleaned message, stack trace, app version, role (customer/store/courier), numeric Malvoya user id when signed in. Also non-fatal reports for API answers 5xx and unreadable bodies (method, path without ids or query, status only). No names, emails, phone numbers, tokens or request bodies. Kept 90 days by Firebase. |
| **App info and performance → Diagnostics** | Yes | No | No | Required | Analytics | Device model, OS version, free memory and disk, orientation, that Crashlytics adds to each report |

- **Not used for advertising or marketing**, and not sold. Play's "Analytics" purpose covers monitoring app health and fixing crashes.
- Crashlytics also sends a random **Crashlytics installation id**: it is in the "Device or other IDs" row of each app below.
- Reports are sent only from release builds (`kReleaseMode`); debug builds switch collection off. An iPhone build without `GoogleService-Info.plist` does not start Crashlytics at all.

---

## 1. Customer app — "Malvoya" (`com.malvoya.customer`)

| Data type (Play name) | Collected | Shared | Ephemeral | Required / optional | Purposes | What it is in Malvoya |
|---|---|---|---|---|---|---|
| **Personal info → Name** | Yes | Yes (the store of the order; courier after accepting) | No | Required | App functionality, Account management | Account name; first name shown on comments and reviews |
| **Personal info → Email address** | Yes | No | No | Required | Account management, App functionality | Sign-in, receipts |
| **Personal info → User IDs** | Yes | No | No | Required | Account management, Analytics | Malvoya user id (also on crash reports), Firebase user id, Google account id (`googleSub`) |
| **Personal info → Address** | Yes | Yes (store, courier after accepting) | No | Optional (pickup orders need none) | App functionality | Delivery address and order notes |
| **Personal info → Phone number** | Yes | No | No | Optional | Account management, App functionality | Phone sign-in and SMS codes (Firebase, Twilio) |
| **Location → Precise location** | Yes | No | No | Optional | App functionality | The map pin of the delivery address (sent to rank stores, price delivery, place orders) and the "notify me when Malvoya opens near me" pin. Not read from GPS. |
| **Financial info → User payment info** | Yes (Stripe SDK) | No (Stripe is a service provider) | No | Optional (only to buy) | App functionality, Fraud prevention, security and compliance | Card or bank details typed into Stripe's PaymentSheet. They go to Stripe; Malvoya never receives them. |
| **Financial info → Purchase history** | Yes | Yes (the store of the order) | No | Required to order | App functionality, Fraud prevention, security and compliance | Orders, refunds, returns, tips, promo/referral use. Kept 6 years (Accounting Act). |
| **Messages → Other in-app messages** | Yes | No | Partly | Optional | App functionality, Developer communications | Order chat with the courier (relayed live, **not stored** = ephemeral) and "Message our team" support requests (stored) |
| **App activity → App interactions** | Yes | No | No | Optional | App functionality | Drop likes, views (one per day), favourites, store follows |
| **App activity → In-app search history** | Yes | No | Yes | Optional | App functionality | Search words are sent to the API to search; not saved to the account |
| **App activity → Other user-generated content** | Yes | No (posting publicly is user-started) | No | Optional | App functionality | Reviews (public with first name), drop comments, reports |
| **Device or other IDs** | Yes | No | No | Required | App functionality, Analytics, Fraud prevention, security and compliance | FCM push token, Firebase installation id, Crashlytics installation id, device data Stripe's SDK collects against fraud |

Also collected: crash logs and diagnostics (see "Crash logs and diagnostics" above).

Not collected: approximate location (not separate from the pin), photos/videos, audio, files, contacts, calendar, health, web browsing, installed apps.

**Deletion:**
- In the app: **Profile → Privacy → Your data → Delete my account** (`Malvoya_customer/lib/screens/profile.dart:626`, button in `screens/privacy_gdpr_screen.dart:477-484`, calls `DELETE /auth/me`).
- On the web: **missing** (see below).

---

## 2. Store app — "Malvoya Store" (`com.malvoya.vendor`)

| Data type | Collected | Shared | Required / optional | Purposes | What it is |
|---|---|---|---|---|---|
| **Personal info → Name** | Yes | Yes (shown to customers as the seller) | Required | App functionality, Account management | Account name; store name (for a private seller this is a person's data) |
| **Personal info → Email address** | Yes | No | Required | Account management, Developer communications | Sign-in; store email |
| **Personal info → User IDs** | Yes | No | Required | Account management, Analytics | As customer |
| **Personal info → Address** | Yes | Yes (customers see it for pickup; couriers for collection) | Required | App functionality | Pickup address of the store |
| **Personal info → Phone number** | Yes | Yes (couriers and customers of an order see the store phone) | Optional | App functionality, Account management | Store phone, phone sign-in |
| **Personal info → Other info** | Yes | No | Required for business sellers | Fraud prevention, security and compliance | Seller type and Y-tunnus (business ID) for Omnibus/DSA/DAC7 checks |
| **Location → Precise location** | Yes | Yes (store position is shown in the customer app) | Optional | App functionality | One GPS fix when "Use my current location" is tapped in store setup |
| **Financial info → Purchase history** | Yes | No | Required | App functionality | The store's sales, refunds, returns |
| **Financial info → Other financial info** | Yes | No | Required to get paid | App functionality, Fraud prevention, security and compliance | Payout amounts, commission, Stripe Connect account id. Bank details and identity checks are typed on **Stripe's own web pages**, not in the app, so they are not "User payment info". |
| **Photos and videos → Photos** | Yes | No (published by the seller) | Optional | App functionality | Product photos, store logo and banner, drop photos (Cloudinary) |
| **Photos and videos → Videos** | Yes | No | Optional | App functionality | Product videos (≤3 × 60 s), drop videos |
| **Files and docs** | Yes | No | Optional | App functionality | CSV file chosen for catalogue import |
| **Messages → Other in-app messages** | Yes | No | Optional | App functionality, Developer communications | Support requests; replies to drop comments |
| **App activity → Other user-generated content** | Yes | No | Optional | App functionality | Product texts, drop captions |
| **Device or other IDs** | Yes | No | Required | App functionality, Analytics | FCM token, Firebase installation id, Crashlytics installation id |

**Deletion:**
- In the app: **Store tab → Delete account** (bottom of the list; `malvoya_vendor/lib/screens/vendor_dashboard.dart:978`, `core/delete_account_tile.dart`).
- Gap: straight after registering, the app pushes `PendingApprovalScreen` (`screens/register.dart:49`), which only has "Sign out". After a restart the dashboard (with Delete account) opens. Add the delete tile to `screens/pending_approval.dart` to be safe.
- On the web: **missing**.

---

## 3. Courier app — "Malvoya Courier" (`com.malvoya.courier`)

| Data type | Collected | Shared | Ephemeral | Required / optional | Purposes | What it is |
|---|---|---|---|---|---|---|
| **Personal info → Name** | Yes | Yes (customer and store of an order) | No | Required | App functionality, Account management | |
| **Personal info → Email address** | Yes | No | No | Required | Account management | |
| **Personal info → User IDs** | Yes | No | No | Required | Account management, Analytics | Malvoya user id (also on crash reports) |
| **Personal info → Phone number** | Yes | No | No | Optional | Account management, App functionality | |
| **Location → Precise location** | Yes | **Yes** (customer and store of the order being carried) | No (latest position stored while online) | Required to work | App functionality, Fraud prevention, security and compliance | GPS while online (foreground service). Deleted on going offline. Handover position kept 30 days. Distance at acceptance used for pay. |
| **Location → Approximate location** | Yes | No | No | Required to work | App functionality | Same stream, used for "nearest first" offers. Tick it too: Play treats them as separate types. |
| **Financial info → Other financial info** | Yes | No | No | Required to get paid | App functionality | Earnings, tips, pay breakdowns, payouts. Bank and KYC data on Stripe's pages, not in the app. |
| **Photos and videos → Photos** | Yes | Yes (the customer of that order) | No | Optional (only door drop-offs) | App functionality, Fraud prevention, security and compliance | Delivery proof photo, private, deleted after 30 days |
| **Messages → Other in-app messages** | Yes | No | Partly | Optional | App functionality, Developer communications | Order chat (not stored) and Help messages (stored) |
| **Device or other IDs** | Yes | No | No | Required | App functionality, Analytics | FCM token, Firebase installation id, Crashlytics installation id |

**Deletion:**
- In the app: **Earnings tab → Delete account** (below "Help and contact"; `malvoya_courier/lib/screens/courier_dashboard.dart:1658`).
- **Gap (blocker):** a courier who is not approved yet only sees `screens/pending_approval.dart`, which has "Check status" and "Sign out" but **no Delete account**. Couriers wait there until an admin approves them, so they cannot delete their account in the app. Add `DeleteAccountTile` to that screen.
- On the web: **missing**.

---

## Web deletion page (required, does not exist)

Play needs, for each app that lets people create an account, a **web link** where users can ask for account and data deletion without reinstalling the app. The page must name the app or developer as on the store listing, list the steps, and say what is deleted and what is kept, and for how long.

Today there is no such page. The old note in `play-store-launch.md` suggested `https://malvoya.com/delete-account`, but **malvoya.com is not under our control** (see `CLAUDE.md`), so that URL cannot be used.

What to add (backend change, not done here):
1. Create `legal/account_deletion.md` (draft below) and add one line to the `DOCS` map in `backend/src/modules/legal/legal.routes.ts`, e.g. `"delete-account": { file: "account_deletion.md", title: "Delete your account" }`.
2. The URL becomes `https://malvoya-api-eu.onrender.com/legal/delete-account`. Use the same URL in all three Data safety forms.
3. Give a working way to ask from the web: a real mailbox you control ([SUPPORT EMAIL]). A small web form that posts to the support module would be better later.
4. Link it from section 8 of the privacy policy.

### Draft for `legal/account_deletion.md`

```markdown
# Delete your Malvoya account / Poista Malvoya-tilisi

This page is for the apps **Malvoya**, **Malvoya Store** and **Malvoya Courier**, published on Google Play by [DEVELOPER NAME AS SHOWN ON GOOGLE PLAY].

## In the app (fastest)

- **Malvoya:** Profile → Privacy → Your data → Delete my account
- **Malvoya Store:** Store tab → Delete account
- **Malvoya Courier:** Earnings tab → Delete account

Orders that are still in progress must be completed or cancelled first.

## Without the app

Email [SUPPORT EMAIL] from the email address or with the phone number of your account, with the subject "Delete my account". Tell us which app you use. We confirm within [7] days and delete the account within one month.

## What is deleted

- Your name, email, phone number, saved addresses and map pins
- Your password, Google link and sign-in sessions
- Likes, favourites, store follows, comments, support messages, "notify me" locations and push tokens
- The text of your reviews (the star rating stays, without your name)
- Couriers: your stored location. Stores: the store is taken off sale and its drops are removed.

## What is kept, and why

- Order and payment records, in anonymised form, for 6 years from the end of the financial year (Finnish Accounting Act 2:10).
- Delivery photos and handover positions until their normal 30-day deletion.
- Security logs for [30] days.
- Payout and identity records that Stripe must keep under anti-money-laundering law (held by Stripe).

Kysymykset: [SUPPORT EMAIL].
```

---

## Mismatches between the code and `legal/privacy_policy.md`

Fix these before publishing; Play compares the Data safety form, the privacy policy and app behaviour.

1. **OpenStreetMap is not listed as a recipient.** The customer app calls `tile.openstreetmap.org` (map tiles) and `nominatim.openstreetmap.org` (address search and reverse lookup of the map pin) straight from the phone (`Malvoya_customer/lib/screens/map_address_picker.dart:60, 111, 166`; `order_detail.dart:489`). The OpenStreetMap Foundation receives the user's IP address, typed addresses and pin coordinates. It is not a contracted processor. The Nominatim policy also asks apps not to send personal data and limits use to 1 request per second for the whole app. Either name OSMF in section 5 as an independent recipient, or (better) route geocoding through the API or a commercial geocoder with a data-processing agreement.
2. **Card data is "collected" in Play's sense.** The privacy policy is right that Malvoya never receives card numbers, but the Stripe SDK inside the app collects them, plus device data for fraud prevention. The old table in `play-store-launch.md` said "not collected by the app"; that would be a wrong Data safety answer. The privacy policy should mention that Stripe's SDK collects device information for fraud prevention.
3. **Features missing from the policy:** drop comments, store follows, the "notify me when Malvoya opens near me" pin (`LaunchAlert`), invite codes/referrals, support requests, order chat (say it is relayed and not stored), product videos, the CSV/Shopify catalogue import, Google sign-in (Google account id) and Google Pay in the payment sheet.
4. **Account deletion leaves data at service providers.** `deleteUserAccount` (`backend/src/modules/auth/auth.service.ts:156`) anonymises the database but:
   - does not delete the **Firebase Authentication user** (phone sign-in keeps the phone number in Firebase);
   - does not delete **Cloudinary files** of a deleted store (product photos, product and drop videos, logo, banner). Drops are marked REMOVED and products hidden, but the files stay.
   Play's account-deletion rules ask you to delete from your own servers and ask processors to delete too. Add both, or list them under "what is kept" with a reason and time limit.
5. **Retention not stated:** support requests, reviews (star rating kept without text after deletion), store name and address kept on past orders, drop comments. Add rows to section 7.
6. **Section 6 still has the region placeholder.** Hosting is already Frankfurt (`malvoya-api-eu`). Replace the bracket with "in Frankfurt, Germany (EU)".
7. **Contact emails are on malvoya.com** (`[privacy@malvoya.com]`, `[support@malvoya.com]`), which is not under our control. Use a mailbox you own.
8. **Controller details are placeholders** (`[COMPANY LEGAL NAME]`, `[Y-TUNNUS]`, address). Play requires the privacy policy to name the developer as on the listing and give a privacy contact. Use the developer account's legal name until a company exists. Do not invent a business ID.
9. **Customer manifest declares location** it never uses. The policy correctly says the customer app does not track location; remove `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` from the customer manifest so the app matches.
10. Small one: section 3 says couriers' "latest position" only is kept. Also say that the handover position is kept 30 days and the distance at acceptance is stored with the job (section 2 says it; section 3 should not contradict it).

---

## Sources

- Data safety definitions (collection, sharing, service providers, ephemeral, SDK data counts, the Analytics purpose): https://support.google.com/googleplay/android-developer/answer/10787469 (read 2026-10-15)
- Account deletion requirements (in-app path + web link, what the page must contain, retention): https://support.google.com/googleplay/android-developer/answer/13327111 (read 2026-10-15)
- Firebase data disclosure (Auth: email, phone, IP, user id; FCM: installation id, tokens; Crashlytics: crash logs, diagnostics, installation UUID): https://firebase.google.com/docs/android/play-data-disclosure (read 2026-10-15; Crashlytics rows added 2026-10-30)
- Stripe mobile SDK data (payment info, device characteristics for fraud, analytics): https://support.stripe.com/questions/stripe-mobile-sdk-privacy-details and the Play SDK Index entry https://play.google.com/sdks/details/com-stripe-stripe-android (read 2026-10-15)
- Google Pay data disclosure for apps: https://developers.google.com/pay/api/android/guides/resources/google-pay-disclosure-requirements (found 2026-10-15)
- Nominatim usage policy: https://operations.osmfoundation.org/policies/nominatim/ ; tile policy: https://operations.osmfoundation.org/policies/tiles/ (read 2026-10-15)
