# Google Play launch pack

Three apps, one developer account:
- `com.malvoya.customer` — "Malvoya"
- `com.malvoya.vendor` — "Malvoya Store"
- `com.malvoya.courier` — "Malvoya Courier"

Build number rule: every upload needs a higher `+N` in `pubspec.yaml` (`1.1.0+2` is the first rebranded build).

## 1. Before the first upload

- [ ] Deploy backend v2.2 to Render. The apps call endpoints the old API doesn't have. See `CLAUDE.md` → Deployment.
- [ ] Publish `legal/privacy_policy.md` at a public URL, e.g. `https://malvoya.com/privacy`, after filling in the company details.
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
| App diagnostics / logs | ✔ | ✔ | ✔ | Security, fraud prevention | – |

- Data is encrypted in transit: **Yes** (HTTPS only).
- Users can request deletion: **Yes**, in the app (Profile → Privacy → Delete account) and by email.
- Data is not sold and not used for advertising.

## 5. Declarations

- **Content rating:** shopping / business, no user-generated public content. Chat is 1:1 and tied to an order.
- **Target audience:** 18+.
- **Location permission** (courier): foreground only while delivering. If background location is added later, Play requires a separate declaration and video.
- **Financial features:** none (payments are handled by Stripe).
- **Account deletion URL:** required by Play, e.g. `https://malvoya.com/delete-account`, describing the in-app option.
