# Activation guide: switch everything on, click by click

Use this together with `docs/release/go-live-readiness.md` (the priorities) and `docs/release/README.md` (app release workflows). **Never paste a secret into a chat**; paste it only into Render, GitHub Secrets or the console it belongs to.

## Step 1 · Render (about 30 minutes)

**Where:** dashboard.render.com → **malvoya-api-eu**.

1. **Settings → Health Check Path:** type `/health/ready` → Save.
2. **Settings → Instance Type:** choose **Standard** before real customers (Starter has only 512 MB of memory).
3. **Environment → Add Environment Variable**, one at a time, then **Save, rebuild and deploy**:

| Key | Value comes from |
|---|---|
| `FIREBASE_PROJECT_ID` | `mivia-4f159` |
| `FIREBASE_SERVICE_ACCOUNT` | Step 2.2 below (the whole JSON file content) |
| `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | cloudinary.com → sign up → Dashboard → "Product environment credentials" |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | your email service (e.g. Brevo: SMTP & API → SMTP; host `smtp-relay.brevo.com`, port `587`) |
| `SUPPORT_EMAIL` | the address where support messages should arrive |
| `DATA_ENCRYPTION_KEY` | the code in `MALVOYA_SECRET_DATA_ENCRYPTION_KEY.txt` on your Desktop (keep a copy safe) |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Step 3 (after the company exists) |
| `SENTRY_DSN` | sentry.io → new Node project → DSN (optional, recommended) |

4. **malvoya-db-eu → Settings:** turn on **storage autoscaling**, and check the backup and recovery options.
5. **Account → Notifications:** get an email when a deploy fails.
6. **Check:** open the admin panel → **System** → **Test connections**. Every line should turn green, and the top should say **Ready for orders** once the steps below are done.

## Step 2 · Firebase console (about 30 minutes)

**Where:** console.firebase.google.com → project **mivia-4f159**.

1. **Build → Authentication → Sign-in method:** enable **Phone**. Enable **Apple** later, for iPhone.
2. **Project settings (⚙️) → Service accounts → Generate new private key.**
   - Open the downloaded file and copy everything.
   - Paste it into Render as `FIREBASE_SERVICE_ACCOUNT`.
   - Delete the file afterwards.
3. **Project settings → Your apps:** for each Android app (`com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier`), click **Add fingerprint** and add:
   - **SHA-1** and **SHA-256** of your upload key. In Android Studio's terminal: `keytool -list -v -keystore <your upload keystore>`; the password is in your local key.properties.
   - After the first Play upload, also add **Play's app-signing** SHA-1/SHA-256 (Play Console → Test and release → App integrity).
4. **Authentication → Settings → SMS region policy:** allow only **Finland** (plus EU countries if needed).
5. **Build → App Check:** register the three Android apps with **Play Integrity**. Turn on enforcement only after testing.
6. **Crashlytics:** open it once so it's enabled (the apps get the code in the next round).
7. **Google Cloud console → Billing → Budgets & alerts:** a budget of e.g. 20 €/month with email alerts.
8. **App Distribution (optional, for testers):** follow `docs/release/README.md` (GitHub secret `FIREBASE_DISTRIBUTION_SA`).
9. **Later, for iPhone:**
   - add 3 iOS apps with the bundle IDs `com.malvoya.customer`, `com.malvoya.vendor` and `com.malvoya.courier`;
   - download each `GoogleService-Info.plist` on the Mac;
   - **Project settings → Cloud Messaging → APNs key** (needs the paid Apple account).

## Step 3 · Stripe (after the Oy is registered)

1. **Activate the account** in the company's name: business details, bank account, ID verification.
2. **Connect → settings:** platform profile as a marketplace with Express accounts, and your branding.
3. **Developers → API keys:** copy the live secret key into Render `STRIPE_SECRET_KEY`.
4. **Developers → Webhooks → Add endpoint:** `https://malvoya-api-eu.onrender.com/api/v1/payments/webhook`. Choose the events the server expects (see `backend/src/modules/payments`), copy the **signing secret** and paste it into Render as `STRIPE_WEBHOOK_SECRET`.
5. **Settings → Payment methods:** cards on; later Google Pay, Apple Pay, MobilePay and Klarna.
6. Tell me when this is done: the customer app needs a build with the live **publishable** key (`pk_live_…`).

## Step 4 · Google Play

1. play.google.com/console → create the developer account (25 USD, ID check).
2. Create the 3 apps and fill in the store listing, data safety and content rating from `docs/play-*.md`.
3. Upload the `.aab` files from `Desktop\Malvoya_Apps` to **Internal testing**, then **Closed testing**. Invite 12+ testers with the message in `docs/release/testers-and-download.md`.
4. After 14 days: **Apply for production**.

## Step 5 · Apple (on your MacBook)

Follow `docs/ios/MAC-SETUP.md`: Xcode, then the simulator, then the Apple Developer Program, then TestFlight.

## Step 6 · Admin account and first data

1. Create your admin account on the live server (the method is in `CLAUDE.md` / `docs/release/README.md`) and turn on **two-step sign-in**.
2. Admin → Settings: set the prices you decided.
3. Admin → Legal: publish the final texts once the lawyer has reviewed them.
