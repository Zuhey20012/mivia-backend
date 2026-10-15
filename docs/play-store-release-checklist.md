# Google Play release checklist (first release)

For: one founder, three apps, first time on Google Play.
Checked against the code and Google's help pages on 2026-10-15. Google changes its menus often, so a menu name may differ slightly.

| App | Package | Play listing name | Build file |
|---|---|---|---|
| Customer | `com.malvoya.customer` | Malvoya | `Desktop\Malvoya_Apps\1_Malvoya_Customer_v1.6.0.aab` |
| Store | `com.malvoya.vendor` | Malvoya Store | `Desktop\Malvoya_Apps\2_Malvoya_Store_v1.6.0.aab` |
| Courier | `com.malvoya.courier` | Malvoya Courier | `Desktop\Malvoya_Apps\3_Malvoya_Courier_v1.6.0.aab` (still building on 2026-10-15; only v1.5.0 was in the folder) |

Other docs: [Data safety answers](play-data-safety.md) · [Permissions and declarations](play-permissions.md) · [Store listing copy](play-store-listing.md) · [Launch pack](play-store-launch.md)

---

## Step 0. Fix these first (blockers)

These were found in the code. Each one is a likely rejection or a broken feature. Details are in the linked docs.

| # | Problem | App | Where | Blocks |
|---|---|---|---|---|
| 1 | **No web page for account deletion.** Play needs a URL in the Data safety form. `malvoya.com` is not ours, so the old idea `malvoya.com/delete-account` cannot work. Add `/legal/delete-account` on the API (draft text in [play-data-safety.md](play-data-safety.md#web-deletion-page-required-does-not-exist)). | all | `backend/src/modules/legal/legal.routes.ts`, new `legal/account_deletion.md` | Data safety form |
| 2 | **Couriers waiting for approval cannot delete their account.** The pending screen has only "Check status" and "Sign out". | courier | `malvoya_courier/lib/screens/pending_approval.dart` | Account deletion policy |
| 3 | **No location disclosure dialog before the permission prompt**, and sharing restarts on app open without a tap. | courier | `courier_dashboard.dart:161-163, 199-206`; `courier_telemetry_service.dart:35-37` | Location / User Data policy, the FGS video |
| 4 | **Privacy policy has placeholders** (controller name, address, contact on malvoya.com, region). Play needs a working policy that names the developer and a privacy contact. | all | `legal/privacy_policy.md` | Every app |
| 5 | **Privacy policy is missing things the apps do** (OpenStreetMap lookups, comments, follows, launch alerts, referrals, support messages, Stripe SDK fraud data). | all | see list in [play-data-safety.md](play-data-safety.md#mismatches-between-the-code-and-legalprivacy_policymd) | Data safety must match policy |
| 6 | **No way to block users** in features with public user content (drop comments, reviews) and order chat. Reviews cannot be reported. Google's UGC policy asks for in-app reporting **and blocking** of users. | customer, store | `widgets/drop_comments_sheet.dart`, store reviews | UGC policy |
| 7 | **Unused location permissions** in the customer manifest. | customer | `Malvoya_customer/android/app/src/main/AndroidManifest.xml:3-4` | Reviewer questions; wrong listing info |
| 8 | **Stripe test key** in the customer app (`pk_test_…`). Fine for testing tracks. **Production must use `pk_live_`** and the live secret key on Render, or nobody can pay. | customer | `Malvoya_customer/lib/config/constants.dart` | Production only |
| 9 | Account deletion does not delete the **Firebase Auth user** or a store's **Cloudinary files**. Fix, or say in the policy and on the deletion page what stays and for how long. | all | `backend/src/modules/auth/auth.service.ts:156` | Account deletion policy |

Already good, checked in code:
- `targetSdk 36` in all three merged manifests. Google needs API 36 for new apps and updates from 31 August 2026.
- No `READ_MEDIA_*`, `CAMERA`, storage, `ACCESS_BACKGROUND_LOCATION` or `AD_ID` permission. Photos use the system picker and the phone's camera app.
- In-app account deletion exists in all three apps (except gap 2).
- Drops and comments can be reported; three reports hide the item; admins moderate.
- Payments are physical goods and delivery, so Stripe is correct. Google says its billing **must not** be used for clothing or delivery.
- Built with Flutter 3.41.2 and AGP 8.11.1, which produce 16 KB-aligned native libraries. Confirm in Play Console → App bundle explorer after upload.

---

## Step 1. Choose the developer account type

You need one Google Play developer account for all three apps. There is a one-time registration fee (pay it in Play Console).

**Personal account** — the realistic choice today.
- You sign up as yourself. Google shows your **legal name, country and developer email** on Google Play.
- In the EU you will also be asked whether you are a "trader" under the Digital Services Act. Malvoya is a business, so the honest answer is yes. Traders' contact details (address, phone, email) are then shown on the listing to EU users. Use contact details you are happy to make public. (Google's own page on this could not be checked on 2026-10-15; follow what Play Console asks.)
- **New personal accounts must run a closed test** before production: at least **12 testers**, opted in **for 14 days in a row**. This applies to each app. See step 7.

**Organisation account** — later.
- Needs a **registered company** and a **D-U-N-S number** (free from Dun & Bradstreet, can take up to 30 days), plus an organisation website and phone.
- Malvoya has **no Y-tunnus yet**, so you cannot open one now. Do not invent company details.
- Organisation accounts do not have the 12-tester rule. When the company exists, you can move the apps to an organisation account with Google's app transfer.

To do:
- [ ] Create the account at play.google.com/console with a Google account you will keep (not a throwaway).
- [ ] Verify the contact email and phone (one-time codes) and your identity.
- [ ] Set the developer name ("Malvoya" is fine as a developer name; the legal name stays yours).
- [ ] Decide the public support email. It must be a mailbox you control: [SUPPORT EMAIL]. Not @malvoya.com.

---

## Step 2. Get the legal pages ready

The Play privacy policy URL is `https://malvoya-api-eu.onrender.com/legal/privacy` (all three apps).

- [ ] Fill every `[PLACEHOLDER]` in `legal/*.md` that you can fill truthfully. Use your own legal name as the controller until a company exists. Leave the Y-tunnus out until you have one.
- [ ] Replace the `@malvoya.com` emails with [SUPPORT EMAIL].
- [ ] Fix the privacy policy gaps listed in [play-data-safety.md](play-data-safety.md).
- [ ] Add the deletion page (blocker 1) and link it from the privacy policy, section 8.
- [ ] Push. The API serves the new text after the next deploy. Open each URL in a phone browser to check.

---

## Step 3. Prepare test accounts for Google's reviewers

Every Malvoya app needs a sign-in, so Play Console asks for **App access** instructions. Reviewers cannot receive your SMS codes, so give **email + password** accounts.

- [ ] Customer: a normal customer account. Mention that payments are in Stripe test mode during testing, and give Stripe's public test card (`4242 4242 4242 4242`, any future date, any CVC) only while the app uses `pk_test_`.
- [ ] Store: a store account that an admin has **approved**, with a few products.
- [ ] Courier: a courier account that an admin has **approved** (otherwise the reviewer only sees "Your account is being reviewed").
- [ ] Write in the instructions: "Malvoya currently operates in Finland. Store lists and jobs depend on location; the test store is at [TEST STORE ADDRESS]."
- [ ] Keep these accounts working. If the password changes, update Play Console. Broken reviewer logins are a top rejection reason.

---

## Step 4. Create each app in Play Console

Repeat for each of the three apps.

- [ ] **Create app**: name (see [listing doc](play-store-listing.md)), default language (English (United Kingdom) or Finnish; add the other as a translation), **App**, **Free**, accept the declarations.
- [ ] **Store listing**: title, short and full description, icon 512 × 512, feature graphic 1024 × 500, at least 2 phone screenshots (plan for 6). Copy in [play-store-listing.md](play-store-listing.md).
- [ ] **Store settings**: category (Customer: Shopping; Store: Business; Courier: Business), contact email.
- [ ] **Countries**: Finland only at first. Add others only when the service really works there.

---

## Step 5. Fill in "App content" (Policy and programs → App content)

| Form | Customer | Store | Courier |
|---|---|---|---|
| Privacy policy | API `/legal/privacy` URL | same | same |
| App access | Restricted; give the test login (step 3) | same | same |
| Ads | **No ads** | No | No |
| Content rating (IARC) | see below | see below | see below |
| Target audience | **18 and over** only | 18+ | 18+ |
| Data safety | [play-data-safety.md](play-data-safety.md) | same | same |
| Advertising ID | **No** | No | No |
| Foreground service permissions | — | — (see note in [permissions doc](play-permissions.md)) | **Location**: text and video in [play-permissions.md](play-permissions.md#play-console-declaration-foreground-service-copy-and-paste) |
| Financial features | None (payments for goods go through Stripe) | None | None |
| Government app / News / Health | No | No | No |

**Content rating (IARC questionnaire).** Answer honestly; the rating is calculated for you.
- Category: pick the one closest to a shopping or business app (for example "All other app types" if no shopping category is offered).
- User interaction: **yes** for the customer app (comments, order chat) and the store app (drops, replies). Courier: order chat with the customer.
- Shares the user's location with other users: **courier yes**, customer no, store yes (the shop's pickup point is public).
- Digital purchases: **no** (physical goods only).
- No violence, sexual content, gambling, drugs.
- If you add features later that change these answers, fill the questionnaire again.

---

## Step 6. Upload the first build (internal testing)

- [ ] Check the build number. `pubspec.yaml` says `1.6.0+8`. Every upload needs a higher `+N` than anything uploaded before for that app.
- [ ] Play Console → app → **Test and release → Testing → Internal testing → Create new release**.
- [ ] Upload the `.aab` from `C:\Users\Zuhey\Desktop\Malvoya_Apps\`. Use the matching file for each app. Do not upload the `.apk` files.
- [ ] On the first upload Play turns on **Play App Signing** (step 6a).
- [ ] Release notes, e.g. "First test version / Ensimmäinen testiversio".
- [ ] Add up to 100 testers by email. Internal builds normally reach testers within minutes.
- [ ] Read the **pre-launch report** (Play runs the app on test devices). Fix crashes it finds.

### Step 6a. Play App Signing and App Links (customer app)

How it works: you sign the `.aab` with your **upload key** (`android/key.properties` + the `.jks` file; both untracked). Google re-signs what it sends to phones with its own **app signing key**. New apps get Google-generated keys; Google's help page (2026) now describes "quantum-ready hybrid signing", where Play may list **several** app signing fingerprints.

Why it matters: the customer app's share links (`/d/`, `/s/`, `/r/`) only open the app if `https://malvoya-api-eu.onrender.com/.well-known/assetlinks.json` lists the fingerprint of the key that signed the installed app. Phones that install from Play get Google's key, not yours.

- [ ] Back up the upload keystore and `key.properties` in two safe places (not in the public GitHub repo). If you lose the upload key, Google can reset it; if you lose access to the account, you lose the apps.
- [ ] Customer app → **Protected with Play → Play Store distribution → Play app signing** (older menus: *Test and release → App integrity → App signing*).
- [ ] Under **App signing key certificate**, copy every **SHA-256** fingerprint shown (one, or more with hybrid signing).
- [ ] On Render → service `malvoya-api-eu` → **Environment** → `ANDROID_APP_SHA256`:
  - **keep the value that is there** (the upload-key fingerprint; it keeps App Links working for test builds you sideload or share as `.apk`);
  - add a comma and the Play fingerprint(s): `AA:BB:…(upload),CC:DD:…(play)`;
  - each fingerprint must be 32 pairs of hex digits separated by colons. `backend/src/config/env.ts:196-199` **silently drops** any entry in another format.
- [ ] Save. Render restarts the service.
- [ ] Open `https://malvoya-api-eu.onrender.com/.well-known/assetlinks.json` and check that all fingerprints are listed. Admin panel → System also shows the number of App Links fingerprints.
- [ ] Install the customer app from the internal test, then check on the phone: `adb shell pm get-app-links com.malvoya.customer` should show `verified` for the host. Play Console → **Grow users → Deep links** also shows the status.
- [ ] Firebase: for **all three** apps, add the Play **SHA-1 and SHA-256** fingerprints in Firebase console → Project settings → Your apps. Without them, Google sign-in and phone sign-in fail on apps installed from Play.
- To read the upload key fingerprint yourself: `keytool -list -v -keystore <path to .jks> -alias <alias from key.properties>`.

---

## Step 7. Closed testing (required for a new personal account)

Rule: at least **12 testers** must be **opted in continuously for 14 days** to a closed test of the app. Then you can apply for production. Testers who leave early do not count, and the 14 days must be in a row. Plan this for each of the three apps.

- [ ] Find at least 12 people (plan 15–20, some drop out). The same people can test all three apps.
- [ ] Make a Google Group (e.g. malvoya-testers) or an email list. Testers need a Google account on an Android phone.
- [ ] **Closed testing → Create track → add the group → create a release** with the same `.aab` (or promote it from internal testing).
- [ ] Send the **opt-in link**. It appears only after the release is reviewed and published to the track. Each tester must open it, tap "Become a tester" and install from Play.
- [ ] Give testers real tasks so the test is meaningful (Google asks about this):
  - customer: browse, pay with a Stripe test card, follow a delivery, start a return, delete a test account;
  - store: set up a test store, add products and a drop, accept an order, mark it ready;
  - courier: go online, accept a job, deliver with a photo, go offline.
  Testers need approved store and courier accounts; approve them in the admin panel.
- [ ] Collect feedback (a form or the group). Keep notes of what you changed. You will be asked.
- [ ] After 14 days: **Dashboard → Apply for production**. Google asks about the test (recruiting, feedback), the app (audience, value, expected installs in year one) and readiness (what you changed). Google says the review "usually takes seven days or less".

---

## Step 8. Production

- [ ] Switch to Stripe **live** keys (blocker 8), build a new `.aab` with a higher `+N`, and test one real small payment and refund yourself.
- [ ] Create a production release. Start with a **staged rollout** (for example 20%) and watch the Android vitals and the admin panel → System page.
- [ ] Review time: Google says reviews can take **up to 7 days, or longer in exceptional cases**, and new developer accounts get more thorough reviews. Plan at least a week of buffer. A new submission during a review can move you back in the queue.
- [ ] After approval: set `MIN_BUILD_*` on Render only when you want to force older builds to update.
- [ ] Keep the old Oregon service only until all testers use a Frankfurt build (see `CLAUDE.md`).

Typical total time for a new personal account: about 3–4 weeks (setup, 14-day closed test, production review).

---

## Common rejection reasons for these app types, and where Malvoya stands

| Reason | Applies to | Status in this project |
|---|---|---|
| Reviewer cannot sign in or gets stuck on "pending approval" | all | **Your action**: approved test accounts with email + password (step 3). |
| Data safety form does not match the app or the privacy policy | all | Answers prepared in [play-data-safety.md](play-data-safety.md). **Privacy policy must be updated first** (blocker 5). Note: card entry in Stripe's sheet counts as "collected". |
| No account deletion in the app or on the web | all | In-app: yes for customer, store, approved couriers. **Missing for pending couriers** (blocker 2). **Web page missing** (blocker 1). |
| Privacy policy unreachable, a PDF, or with placeholders | all | Live HTML page at `/legal/privacy`; **placeholders remain** (blocker 4). |
| Location used without prominent disclosure | courier | **Missing dialog** (blocker 3). A one-line hint exists (`courier_dashboard.dart:1210-1211`). |
| Foreground service declaration missing, vague, or the video does not show the feature | courier | Text ready in [play-permissions.md](play-permissions.md). **Record the video after the dialog exists.** |
| Permissions requested but not used | customer | **Location declared, never used** (blocker 7). |
| User-generated content without report and block | customer, store | Report: yes for drops and comments, human moderation, terms forbid misuse. **Block users: missing; reviews: no report button** (blocker 6). Terms (`legal/terms_of_service.md` §5, §9) should also cover comments. |
| Broken payments / test mode in production | customer | Test key today; **switch before production** (blocker 8). |
| Misleading listing (fake ratings, "#1", stock photos of other brands) | all | Listing copy avoids it. Use your own test content in screenshots. |
| Impersonation or trademark use | all | Do not show other brands' logos or names in test stores or screenshots. |
| Target API too low | all | OK (36). |
| Crashes in the pre-launch report | all | Check after the first internal upload. |
| Wrong use of Google Play billing | customer | OK: clothes and delivery must not use Play billing; Stripe is used. |

---

## Sources (all read on 2026-10-15)

- Testing requirement for new personal accounts (12 testers, 14 days, production application, ~7-day review): https://support.google.com/googleplay/android-developer/answer/14151465
- Set up internal, closed and open tests: https://support.google.com/googleplay/android-developer/answer/9845334
- Account types and D-U-N-S: https://support.google.com/googleplay/android-developer/answer/13634885
- Information required to create an account, and what is shown publicly: https://support.google.com/googleplay/android-developer/answer/13628312
- Target API level (API 36 from 31 Aug 2026): https://support.google.com/googleplay/android-developer/answer/11926878
- Play App Signing, fingerprints, hybrid signing, upload key reset: https://support.google.com/googleplay/android-developer/answer/9842756
- Account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Publishing and review times (up to 7 days or longer): https://support.google.com/googleplay/android-developer/answer/9859751 and https://support.google.com/googleplay/android-developer/answer/9859654
- Content rating questionnaire: https://support.google.com/googleplay/android-developer/answer/9859655
- User-generated content policy (report and block): https://support.google.com/googleplay/android-developer/answer/9876937
- Payments policy (no Play billing for physical goods and services): https://support.google.com/googleplay/android-developer/answer/9858738
- 16 KB page sizes: https://developer.android.com/guide/practices/page-sizes
- DSA trader disclosure (Google's Chrome Web Store FAQ, used as the closest Google source; the Play help page could not be fetched): https://developer.chrome.com/docs/webstore/program-policies/trader-verification-faq
