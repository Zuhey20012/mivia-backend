# Google Play launch pack

Three apps, one developer account:
- `com.malvoya.customer` — "Malvoya"
- `com.malvoya.vendor` — "Malvoya Store"
- `com.malvoya.courier` — "Malvoya Courier"

Build number rule: every upload needs a higher `+N` in `pubspec.yaml` (`1.2.0+3` is the current build).

## 1. Before the first upload

- [x] Backend v2.3 deployed on Render (drops, payouts, reviews, support, legal pages).
- [x] Legal documents are published by the API: `https://malvoya-api-n065.onrender.com/legal/privacy` (use this as the Play privacy policy URL), `/legal/terms`, `/legal/sellers`, `/legal/couriers`.
- [ ] Fill in the `[PLACEHOLDERS]` in `legal/*.md` (company name, Y-tunnus, address, commission) and push; the pages update on the next deploy.
- [ ] Cloudinary account (photos/videos): `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` on Render. Without them uploads say they are switched off.
- [ ] Firebase service account for push: `FIREBASE_SERVICE_ACCOUNT` on Render (Project settings → Service accounts → Generate new private key; paste the JSON).
- [ ] Stripe Connect enabled (Stripe Dashboard → Connect → Get started, Express accounts, Finland) so stores and couriers can be paid.
- [ ] Stripe **live** keys: `STRIPE_SECRET_KEY` on Render, the `pk_live_` key in `Malvoya_customer/lib/config/constants.dart`, and the webhook at `/api/v1/payments/webhook`.
- [ ] Enable **Play App Signing** and keep the upload key (`android/app/malvoya-release-key.jks`) backed up in two safe places.
- [ ] Add the Play App Signing SHA-1 and SHA-256 to each Firebase Android app, or Google and phone sign-in will fail on Play builds.

## 2. Testing tracks

1. **Internal testing** (up to 100 testers, available within minutes): upload each `.aab` and add the team's emails.
2. **Firebase App Distribution**: upload the `.apk` files for testers outside Play.
3. **Closed testing**: new personal developer accounts must run a closed test with at least 12 testers for 14 days before production access.

## 3. Store listing — suggested copy

**Malvoya:** *Local fashion, delivered today.*
Shop independent boutiques, vintage and second-hand stores near you. Secure payment, live courier tracking, 14-day returns.

**Malvoya Store:** *Sell locally with Malvoya.*
Open your store, list products and get paid orders delivered by local couriers.

**Malvoya Courier:** *Deliver on your own schedule.*
Go online when you want, see the fee before you accept, and deliver fashion across your city.

Assets per app:
- 512 × 512 icon (`assets/brand/icon.png`, downscaled)
- 1024 × 500 feature graphic
- at least 2 phone screenshots

## 4. Data safety form (must match the privacy policy)

| Data type | Customer | Store | Courier | Purpose | Shared with |
|---|---|---|---|---|---|
| Name, email, phone | ✔ | ✔ | ✔ | Account, app functionality | Store/courier of an order (name only) |
| Approximate/precise location | Delivery address only | Store location | Precise, only while online | App functionality | Customer and store of the active order |
| Purchase history | ✔ | ✔ | – | App functionality, legal obligations | Store of the order |
| Payment info | Processed by Stripe; **not collected by the app** | – | – | – | – |
| Photos and videos | – | Product photos, drop videos | Delivery photo (door drop-offs) | App functionality | Store content is public in the app; delivery photos only to the customer |
| App activity (likes, views, favourites, reviews) | ✔ | – | – | App functionality | Review text and first name public on the store page |
| Messages (order chat) | ✔ | – | ✔ | App functionality | The other party of the order; not stored |
| Device ID (push token) | ✔ | ✔ | ✔ | App functionality (notifications) | Google Firebase (processor) |
| App diagnostics / logs | ✔ | ✔ | ✔ | Security, fraud prevention | – |

- Data is encrypted in transit: **Yes** (HTTPS only).
- Users can request deletion: **Yes**, in the app (Profile → Privacy → Delete account) and by email.
- Data is not sold and not used for advertising.

## 5. Declarations

- **Content rating:** shopping. Stores post public videos and photos (drops) and customers post reviews: answer **yes** to user-generated content, with reporting in the app and human moderation (admin panel → Moderation). Chat is 1:1, tied to an order and not stored.
- **Target audience:** 18+.
- **Location permission** (courier): no background-location permission. While online, the app runs a **foreground service of type location** with a permanent notification. Play Console → App content → *Foreground service permissions*: declare `FOREGROUND_SERVICE_LOCATION` with the use case "navigation / delivery tracking while the courier is online" and a short video of going online, the notification appearing, and going offline.
- **Camera/photos:** the store and courier apps use the system photo picker and camera app (no camera or storage permission declared).
- **Financial features:** none (payments are handled by Stripe).
- **Account deletion URL:** required by Play, e.g. `https://malvoya.com/delete-account`, describing the in-app option.
