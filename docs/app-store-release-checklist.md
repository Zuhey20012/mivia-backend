# Apple App Store release checklist

For the three Flutter apps: **Malvoya** (customer), **Malvoya Store** (vendor) and **Malvoya Courier**. Written 2026-10-17 from the code in this repository and Apple's pages (sources at the end, each with the date read).

None of the apps has been built for iOS yet. The `ios/` folders are the Flutter template with Malvoya's names, launch screen, icons and purpose strings. Several things below **block** an App Store upload or review; they are marked **Blocker**.

**Update 2026-10-25 (iOS preparation round):** the projects are now set up to build and run on the iPhone simulator on a Mac. Step-by-step guide: [`docs/ios/MAC-SETUP.md`](ios/MAC-SETUP.md). Done in the code: G1, G2, G3, G5 (placeholders), G6 (placeholder), G7, G8 (customer: Sign in with Apple; store/courier: no Google on iPhone), G9, G11 (app side), G12, G13. Still open: G4 (add `GoogleService-Info.plist` on the Mac), G10, G14, G15, and the backend work listed in sections 6 and 10. The status column below says which.

---

## 0. Gaps found in the iOS projects

| # | Gap | Where | Apps | Severity | Status (2026-10-25) |
|---|---|---|---|---|---|
| G1 | Bundle ID is `com.example.miviaApp` (same in all three; RunnerTests `com.example.miviaApp.RunnerTests`). Apple refuses `com.example` IDs, and three apps cannot share one ID. Set `com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier` (same as Android) | `ios/Runner.xcodeproj/project.pbxproj`, `PRODUCT_BUNDLE_IDENTIFIER` (lines 375, 554, 576 and the RunnerTests lines 391, 408, 423) | all | **Blocker** | **Done**: `com.malvoya.customer/vendor/courier` (+ `.RunnerTests`) in all build configurations |
| G2 | `CFBundleName` is `mivia_app` (old name). Change to `Malvoya`, `Malvoya Store`, `Malvoya Courier` (max 15 characters is the guidance; `Malvoya Courier` is 15) | `ios/Runner/Info.plist` | all | Fix | **Done**: `CFBundleName` = `CFBundleDisplayName` = Malvoya / Malvoya Store / Malvoya Courier |
| G3 | iPad is enabled (`TARGETED_DEVICE_FAMILY = "1,2"`). Apple then requires 13" iPad screenshots and reviews the iPad layout. Unless you want iPad, set `TARGETED_DEVICE_FAMILY = 1` (iPhone only) | `project.pbxproj` (3 build configurations) | all | Strongly recommended | **Done**: `TARGETED_DEVICE_FAMILY = 1` in all configurations (no plugin needs iPad) |
| G4 | No `GoogleService-Info.plist`: Firebase is not set up for iOS. Push (FCM), phone sign-in and Apple sign-in through Firebase do not work without it. `Firebase.initializeApp()` is wrapped in `try`, so the apps start but these features fail | `ios/Runner/` | all | **Blocker** for sign-in and push | Open: the owner adds the plist on the Mac (MAC-SETUP section 9); it is git-ignored. Without it the apps start, hide Google/Apple/Firebase phone sign-in and run without push (`SignInSetup` in `malvoya_core`; `AppDelegate.swift` stops iOS handing pushes to the firebase_auth plugin, which would crash without Firebase) |
| G5 | Google sign-in needs the iOS OAuth client: `GIDClientID` and a URL type with the reversed client ID in `Info.plist`. Missing, so tapping "Continue with Google" fails on iOS | `ios/Runner/Info.plist` | all | **Blocker** (if Google stays on iOS) | **Done (placeholders)**: `GIDClientID`, `GIDServerClientID` and the reversed-client-ID URL scheme come from `ios/Flutter/Malvoya.xcconfig` (customer). The Google button is hidden on iPhone until they are filled. Store/courier: no Google on iPhone |
| G6 | Firebase phone sign-in on iOS needs APNs (silent push) or the reCAPTCHA fallback, which needs a URL type with the encoded app ID from `GoogleService-Info.plist` | `Info.plist`, Firebase console | all | **Blocker** for phone sign-in | **Done (placeholder)**: `FIREBASE_ENCODED_APP_ID` URL scheme in `Malvoya.xcconfig` (all apps). Until filled: customer falls back to the server's SMS code, store/courier hide phone sign-in on iPhone |
| G7 | No entitlements file: no Push Notifications (`aps-environment`), no Sign in with Apple, no Associated Domains | `ios/Runner/Runner.entitlements` (add in Xcode/Codemagic as capabilities) | all | **Blocker** for push | **Done**: `ios/Runner/Runner.entitlements` (aps-environment development; customer also Sign in with Apple and `applinks:malvoya-api-eu.onrender.com`), set by `CODE_SIGN_ENTITLEMENTS` in `Malvoya.xcconfig`; `RunnerPersonalTeam.entitlements` (empty) for free-account device tests. `UIBackgroundModes` remote-notification in all apps |
| G8 | Sign in with Apple / Guideline 4.8: the apps offer Google sign-in but no equivalent option on iOS | see section 6 | all | **Blocker** (review) | **Done**: customer shows Sign in with Apple on iPhone (Option A); store and courier hide Google on iPhone (Option B). Backend `appleSub` still to do (section 6) |
| G9 | Courier location stops in the background on iOS: the position stream uses plain `LocationSettings` on iOS (no `AppleSettings`, no `allowBackgroundLocationUpdates`), and `UIBackgroundModes` has no `location` | `malvoya_courier/lib/services/courier_telemetry_service.dart` line ~57, `Info.plist` | courier | **Blocker** (the product does not work) | **Done**: `UIBackgroundModes` location and `AppleSettings` with background updates and the blue indicator **only while an order is being carried** (between jobs: app open only). Android unchanged |
| G10 | Customer app: drop comments are user-generated content, but users cannot **block** another user (report and auto-hide exist). Guideline 1.2 asks for filtering, reporting, blocking and contact info | customer app + backend `modules/drops/social.ts` | customer | Likely rejection | Open |
| G11 | Universal Links: the API publishes `/.well-known/assetlinks.json` (Android) but no `/.well-known/apple-app-site-association` | `backend/src/modules/share/share.routes.ts` | customer | Needed for `/s/`, `/r/`, `/d/` links | App side **done** (Associated Domains entitlement, `FlutterDeepLinkingEnabled` false as on Android). Backend route still to do (section 10) |
| G12 | `ITSAppUsesNonExemptEncryption` not set: App Store Connect asks the export questions for every build | `Info.plist` | all | Fix (section 12) | **Done** in all three `Info.plist` |
| G13 | No `Podfile` yet. Flutter creates it on the first iOS build (`platform :ios, '13.0'`). Commit it after the first CI build | `ios/Podfile` | all | Normal | **Done**: `ios/Podfile` committed (`platform :ios, '15.0'`; post_install sets every pod to 15.0). Commit `Podfile.lock` after the first `pod install` on the Mac |
| G14 | No app privacy manifest (`PrivacyInfo.xcprivacy`) for the Runner target. The plugins ship their own; add one for the app itself declaring no tracking (section 11) | `ios/Runner/` | all | Recommended | Open |
| G15 | Store notifications on iOS: the insistent new-order alarm (Android `FLAG_INSISTENT`, the `new_orders` channel) has no iOS equivalent; iOS plays the push sound once. Time-sensitive notifications (entitlement `com.apple.developer.usernotifications.time-sensitive`) are the closest | store app | store | Product gap | Open |

Already fine:

- Deployment target: raised to **iOS 15.0** (2026-10-25) in `project.pbxproj` and the Podfile. The plugins need at most iOS 14 today (`file_picker_darwin` 2.2.0); firebase_core 3.15 (Firebase iOS SDK 11), stripe_ios 10.2 (Stripe iOS 23.27), video_player_avfoundation, app_links, url_launcher_ios and image_picker_ios need 13, google_sign_in_ios 12, geolocator_apple 11. iOS 15 also covers firebase_core 4.x (Firebase iOS SDK 12 needs iOS 15).
- Purpose strings: done in this change, English in `Info.plist` and English + Finnish in `ios/Runner/{en,fi}.lproj/InfoPlist.strings`, registered in the Xcode project (section 8).
- Launch screen and app icons in brand colours (no white flash): done in this change.
- In-app account deletion exists in all three apps (section 7).

---

## 1. Apple Developer Program

- **Cost:** 99 USD per membership year, charged in local currency (in Finland the price is shown in euros at enrolment). One membership covers all three apps.
- **Individual or organisation:**
  - **Individual** (also a sole trader / toiminimi): your legal name as on your ID, an Apple Account with two-factor authentication. Your **personal name** is shown as the seller on the App Store. No D-U-N-S number.
  - **Organisation** (for example an Oy): must be a legal entity that can sign contracts (Apple does not accept trade names or DBAs), needs a **D-U-N-S number**, a work email on the company's domain and a public, working website on that domain. The company name is shown as the seller.
  - Malvoya has no Y-tunnus yet, so today only **individual** enrolment is possible. If you plan to found a company before launch, wait and enrol as an organisation: moving an individual account to an organisation later goes through Apple support and takes time.
- **D-U-N-S:** free from Dun & Bradstreet; Apple has a lookup/request tool in the enrolment flow. It needs the company to be registered (Y-tunnus) first. Allow some business days for D&B and then for Apple to see the number.
- **EU trader status (DSA):** apps without a declared trader status are removed from the EU storefronts. If Malvoya is a business (it is: commission and fees), you declare yourself a **trader**, and Apple shows your **address, phone number and email** on the product page. For an individual account that means your own contact details. Use a business address and phone you are happy to publish, which is one more reason to enrol as a company.
- After enrolment: App Store Connect → Agreements, Tax and Banking → accept the **Free Apps** agreement (paid apps/IAP are not used). Fill in the tax forms only if you ever sell digital content.

## 2. Building iOS without a Mac

You do not need to own a Mac. Recommended: **Codemagic** (Flutter-focused CI with hosted Macs).

| | Codemagic |
|---|---|
| Free | 500 macOS M2 build minutes per month, 1 build at a time (individual accounts) |
| Pay as you go | Mac mini M2 0.095 USD/min, M4 0.114 USD/min |
| Typical Flutter iOS build | 10–20 min, so the free minutes cover roughly 25–50 builds a month across the three apps |

Steps:

1. Fix G1–G3 first (bundle IDs, names, iPhone only). These are small edits to `project.pbxproj` and `Info.plist`.
2. Enrol in the Developer Program (section 1). In **Certificates, Identifiers & Profiles → Identifiers**, register three App IDs: `com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier`. Tick **Push Notifications**, **Sign In with Apple** (if you use it, section 6) and, for the customer app, **Associated Domains**.
3. In **App Store Connect → Apps → +**, create the three apps with those bundle IDs (name, primary language Finnish or English, SKU like `malvoya-customer`).
4. In **App Store Connect → Users and Access → Integrations → App Store Connect API**, create a team API key with the **App Manager** role. Download the `.p8` (you can only download it once) and note the Issuer ID and Key ID.
5. On codemagic.io: sign up, add the Git repository, then **Teams → Integrations → Developer Portal** and paste the API key. Codemagic then creates the distribution certificate and provisioning profiles itself ("automatic code signing").
6. Add a `codemagic.yaml` at the repository root with one workflow per app (the apps are in sub-folders):

   ```yaml
   workflows:
     customer-ios:
       name: Malvoya customer iOS
       working_directory: Malvoya_customer
       instance_type: mac_mini_m2
       integrations:
         app_store_connect: <name of the API key in Codemagic>
       environment:
         flutter: stable
         xcode: latest          # must be Xcode 26 or later (Apple's rule since 2026-04-28)
         ios_signing:
           distribution_type: app_store
           bundle_identifier: com.malvoya.customer
         groups: [firebase_ios]  # GoogleService-Info.plist as a secure file/variable, never committed
       scripts:
         - name: Firebase config
           script: echo $GOOGLE_SERVICE_INFO_PLIST_CUSTOMER | base64 --decode > ios/Runner/GoogleService-Info.plist
         - name: Signing
           script: xcode-project use-profiles
         - name: Dependencies
           script: flutter pub get
         - name: Build
           script: |
             flutter build ipa --release \
               --build-number=$(($(app-store-connect get-latest-testflight-build-number "$APP_STORE_APPLE_ID") + 1)) \
               --export-options-plist=/Users/builder/export_options.plist
       artifacts:
         - build/ios/ipa/*.ipa
       publishing:
         app_store_connect:
           auth: integration
           submit_to_testflight: true
   ```

   Copy it for `malvoya_vendor` (`com.malvoya.vendor`) and `malvoya_courier` (`com.malvoya.courier`). `APP_STORE_APPLE_ID` is the numeric Apple ID of each app in App Store Connect (App Information).
7. Run the workflow. `ios/Podfile` is committed (G13); the first run creates `Podfile.lock`: download it from the build artefacts or let the build commit it, so later builds are reproducible. Fill `ios/Flutter/Malvoya.xcconfig` (Firebase encoded app ID, Google client IDs) for the build, see `docs/ios/MAC-SETUP.md` section 14.
8. iOS build numbers are independent of Android's. The app gate (`MIN_BUILD_*`) compares Android build numbers; check how `core/app_gate.dart` behaves with iOS build numbers before you set a minimum.

Alternatives: **Xcode Cloud** (Apple, 25 compute hours a month included with the membership, but you still need Xcode on a Mac to set it up), GitHub Actions macOS runners, or a rented cloud Mac (MacinCloud and similar) if you prefer clicking through Xcode.

**With a Mac (yours or borrowed):** install Xcode 26+ from the App Store, CocoaPods (`brew install cocoapods`), Flutter. Then `cd Malvoya_customer && flutter build ipa`, open `ios/Runner.xcworkspace`, sign in with your Apple Account in Xcode → Settings → Accounts, tick "Automatically manage signing" for the Runner target with your team, and upload with **Xcode → Product → Archive → Distribute App** or the **Transporter** app.

## 3. Firebase on iOS (push, phone sign-in, Apple sign-in)

For each app (one Firebase iOS app per bundle ID):

1. Firebase console → Project settings → **Add app → iOS**, bundle ID `com.malvoya.<app>`. Download `GoogleService-Info.plist`. Keep it out of git; give it to Codemagic as a base64 secure variable (step 6 above) or add it in Xcode to the Runner target.
2. Apple Developer → **Keys → +** → enable **Apple Push Notifications service (APNs)**. Download the `.p8` once, note the Key ID and your Team ID. One key works for all your apps and both environments.
3. Firebase console → Project settings → **Cloud Messaging → Apple app configuration → APNs authentication key → Upload** (the `.p8`, Key ID, Team ID). Do it for each of the three iOS apps.
4. Capabilities on each App ID and in the build: **Push Notifications**, and **Background Modes → Remote notifications** (`UIBackgroundModes` `remote-notification`) so FCM data messages and phone-auth silent pushes arrive. The courier also needs **Location updates** (section 8).
5. Phone sign-in: with APNs set up, Firebase verifies the device silently. Also add the reCAPTCHA fallback URL type: in `Info.plist` → `CFBundleURLTypes`, the **Encoded App ID** shown in the Firebase console for the iOS app (`app-1-…-ios-…`).
6. Google sign-in (if kept on iOS, see section 6): create an iOS OAuth client in Google Cloud (or take `CLIENT_ID` / `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`), add `GIDClientID` = client ID and a `CFBundleURLTypes` entry with the reversed client ID to `Info.plist`. The backend verifies Google tokens against `env.googleClientId`; Google ID tokens from the iOS client have the **iOS client ID** as audience, so the backend must accept a list of client IDs (Android/web + iOS). This is a backend change. (2026-10-25: the customer app passes `GOOGLE_SERVER_CLIENT_ID` from `ios/Flutter/Malvoya.xcconfig` as `serverClientId`; with it Google's iOS SDK asks for an ID token addressed to that web client ID, which the API already accepts. Check once on the Mac; if the token still carries the iOS client ID, add it to the backend's accepted audiences.)

## 4. Signing, certificates, TestFlight

- **Distribution certificate** (Apple Distribution) and one **App Store provisioning profile** per bundle ID. Codemagic or Xcode creates and renews them automatically; you do not need a Mac for that with the API key.
- Keep the API key `.p8`, the APNs `.p8` and any exported `.p12` in a password manager. Never commit them.
- **TestFlight:** every uploaded build appears under TestFlight after processing (5–30 min).
  - **Internal testers** (up to 100 people in your App Store Connect team): no review, available at once.
  - **External testers** (up to 10 000, by email or a public link): the first build of each version goes through a short **Beta App Review**; fill in "What to test", a contact email and a demo account.
  - Builds expire after 90 days.
- Answer export compliance once per app (section 12) or set the `Info.plist` key so TestFlight does not ask every time.

## 5. App Store Connect listing

Per app and per language (Finnish and English):

- Name (30 chars), subtitle (30), promotional text (170), description (4000), keywords (100, comma-separated), support URL (**required**, must work: for example the legal pages' host or a simple support page), marketing URL (optional), privacy policy URL: `https://malvoya-api-eu.onrender.com/legal/privacy`.
- Reuse the copy from `docs/play-store-listing.md`; drop the Play-specific notes. The same "no claims" rules apply (Guideline 2.3.7: no prices, other apps' names, irrelevant keywords in the name or keywords).
- Screenshots: the iPhone 6.1" size (1206 × 2622 or 1179 × 2556) is required; take them on a real iPhone running a TestFlight build and frame them with `docs/store-assets/screenshot-kit/`. 13" iPad screenshots are required only while iPad stays enabled (G3).
- App previews (optional): `docs/store-assets/promo-video-plan.md`.
- Icon: comes from the build (`AppIcon.appiconset`, 1024 px without alpha). `docs/store-assets/<app>/app-store-icon-1024.png` is the same image.
- **Age rating**: answer the new questionnaire (Apple changed it in 2026). The customer app has user-generated content (comments, drop videos from stores) and in-app purchases of physical goods; the expected result is 12+/13+ depending on your answers about UGC. The apps are for 18+ by their own terms; you can additionally set "age restrictions" in the questionnaire.
- **Category:** customer Shopping; Store Business; Courier Business.
- **App Review information:** a contact, a phone number, notes, and **demo accounts** (section 13).

## 6. Sign in with Apple and Guideline 4.8 (Blocker)

**What Apple requires today** (Guideline 4.8, read 2026-10-16): an app that uses a third-party or social login service, **Google Sign-In** is named, to set up or authenticate the user's primary account "must also offer as an equivalent option another login service" that:

1. limits data collection to the user's name and email address,
2. lets users keep their email address private when setting up the account, and
3. does not collect interactions with the app for advertising without consent.

Sign in with Apple meets all three (Hide My Email). Apple no longer insists on Sign in with Apple specifically, but in practice it is the only common service with private email. None of the exceptions fits Malvoya: the apps do not use *only* Malvoya's own account system (they offer Google), and the "business app" exception covers apps that require an existing *enterprise or education* account, not a personal Google account. Malvoya's own email + password and phone sign-in do not count as the "equivalent option", because they are not a login service that keeps the email private.

**State of the code:**

| | Customer | Store | Courier |
|---|---|---|---|
| Google sign-in button | yes (`screens/login.dart`) | yes | yes |
| "Google account" link tile (settings) | yes | yes | yes |
| `sign_in_with_apple` package | in pubspec | in pubspec | in pubspec |
| Apple sign-in method | `AuthService.loginWithApple()` now uses `signInWithProvider(AppleAuthProvider()..addScope('email')..addScope('name'))` (Firebase handles the nonce) → `POST /auth/apple {idToken: <Firebase ID token>, role: "CUSTOMER", name?}`; `name` is the name Apple gave on the first sign-in, which Firebase keeps as the display name | none | none |
| Apple button in the UI | **yes, iPhone only** (2026-10-25, `screens/login.dart`: above Google, Apple's black/white style, 54 pt like Google; shown once Firebase is set up) | no (Google hidden on iPhone) | no (Google hidden on iPhone) |
| Backend | `POST /auth/apple` (`social.service.ts#loginWithApple`): verifies a **Firebase** ID token, finds the user **by email only**, creates new accounts with the given `role` | same route | same route |

**Two ways to pass review. Choose per app.**

**Option A: add Sign in with Apple on iOS (recommended for the customer app).**

App changes (Dart, all three apps):

1. Show a **Sign in with Apple** button on iOS only (`Platform.isIOS`), as prominent as the Google button (same size, next to it). Use `SignInWithAppleButton` from the package or Apple's button style; follow Apple's Human Interface Guidelines for the button (black/white, Apple logo, "Sign in with Apple" / "Jatka Applella" localised by the system).
2. Replace the manual Firebase credential in `loginWithApple()` with `FirebaseAuth.instance.signInWithProvider(AppleAuthProvider()..addScope('email')..addScope('name'))`. It handles the nonce (the current code passes no nonce, which Firebase can reject), and returns `additionalUserInfo?.authorizationCode`, needed for token revocation.
3. Send the name Apple gives on the **first** sign-in only (`givenName`, `familyName`) to `/auth/apple` together with the Firebase ID token and `role` (`VENDOR` / `COURIER` in those apps), because the Firebase token usually has no name.
4. Store and courier: copy the method from the customer app's `auth_service.dart` (they already use `firebase_auth` for phone sign-in).
5. Account deletion (all apps): before calling `DELETE /auth/me`, if the user signed in with Apple, call `FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code)` with a fresh authorization code (sign the user in with Apple once more in the deletion confirmation if no code is at hand). Apple's account-deletion page says apps "should use the Sign in with Apple REST API to revoke user tokens".
6. Settings: an "Apple ID" tile like the Google one is optional; not needed for review.

Backend changes:

1. Add `User.appleSub` (unique, nullable) like `googleSub`. In `loginWithApple`, read the Apple user id from the Firebase token (`decoded.firebase.identities['apple.com'][0]`), find the user by `appleSub` first, then by verified email, and set `appleSub` on first use. With Hide My Email, the email is a `@privaterelay.appleid.com` address, so matching by email alone works only as long as the user keeps sharing the same relay address.
2. Accept an optional `name` in `POST /auth/apple` and use it for new accounts instead of "Customer".
3. Account deletion (`deleteUserAccount`) clears `appleSub`.
4. Email to relay addresses: in Apple Developer → **Sign in with Apple for Email Communication**, register the sending domain and the From address your SMTP uses (with SPF/DKIM), otherwise receipts and codes to `@privaterelay.appleid.com` addresses are dropped.
5. Optional: a server-to-server notification endpoint (Apple sends "email disabled", "consent revoked", "account deleted" events). Register it on the Services ID.

Apple / Firebase setup:

1. App ID capability **Sign In with Apple** for each bundle ID; the entitlement `com.apple.developer.applesignin` = `Default` in the build (Codemagic adds it from the capability; with Xcode add the capability).
2. Firebase console → Authentication → Sign-in method → **Apple** → enable. For token revocation fill in the Services ID, Apple Team ID, Key ID and the private key of a **Sign in with Apple** key (Apple Developer → Keys → enable Sign in with Apple).

**Option B: do not offer Google sign-in on iOS.**

Hide the Google button and the "Google account" link tile when `Platform.isIOS`. The iOS apps then use only Malvoya's own sign-in (email + password, one-time code, phone number via Firebase), which is the 4.8 exception "your app exclusively uses your company's own account setup and sign-in systems". No Apple setup, no backend change. Users who created their account with Google on Android can still sign in on iPhone with a one-time email code (`/auth/otp`) as long as the code path allows Google-created accounts (they are verified accounts, so `assertVerifiedSignInAllowed` lets them through).

Option B is the smallest change and is enough for the **store** and **courier** apps. For the **customer** app, Option A gives a better first-run experience and most of the code is already there.

Sources: Guideline 4.8 and 5.1.1(v) (read 2026-10-16); Apple, Offering account deletion in your app (read 2026-10-16); Firebase, Federated identity & social sign-in for Flutter (read 2026-10-17).

## 7. Account deletion (Guideline 5.1.1(v))

- Rule: "If your app supports account creation, you must also offer account deletion within the app." It must delete the account and its personal data, not just deactivate it; a link to a web page that completes the deletion is acceptable, a support email or phone call is not.
- Status: all three apps have it in-app (customer: Profile → Privacy → Delete account; store and courier: `core/delete_account_tile.dart`). The backend anonymises the user and keeps order records because the Accounting Act requires it. Apple accepts keeping legally required data **if the app tells the user** what is kept. Check that the deletion confirmation text says so (for example "Orders are kept for 6 years because the Accounting Act requires it; your name and contact details are removed").
- Sign in with Apple users: revoke the Apple token on deletion (section 6, Option A step 5).
- In the review notes, say where the button is: "Account deletion: Profile → Privacy → Delete account".

## 8. Location and background modes (courier) — purpose strings

Purpose strings now in the projects (English in `Info.plist`, English + Finnish in `InfoPlist.strings`):

| Key | Customer | Store | Courier |
|---|---|---|---|
| `NSLocationWhenInUseUsageDescription` | yes | yes | yes (rewritten: it now names the job offers and the store check-in, not only deliveries) |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | yes (says location is not used in the background) | yes (same) | yes (background use while online) |
| `NSCameraUsageDescription` | – | yes (product photos, videos) | yes (delivery photo) |
| `NSMicrophoneUsageDescription` | – | yes (sound of recorded videos) | – |
| `NSPhotoLibraryUsageDescription` | – | yes | yes |

Why the "Always" string is in all three: the `geolocator` plugin contains code that can request Always permission, and App Store Connect rejects uploads whose binary references a permission API without its purpose string (ITMS-90683). The plugin asks for **When In Use** whenever that key exists (checked in `geolocator_apple` 2.3.14 `PermissionHandler.m`), so users never see the Always prompt. If you prefer to remove the code instead, add `BYPASS_PERMISSION_LOCATION_ALWAYS=1` to `GCC_PREPROCESSOR_DEFINITIONS` for the `geolocator_apple` pod in the Podfile `post_install` and delete the Always key from the customer and store apps.

**Courier background location (G9), two changes together:**

1. `Info.plist`: add
   ```xml
   <key>UIBackgroundModes</key>
   <array>
       <string>location</string>
       <string>remote-notification</string>
   </array>
   ```
   (and the **Background Modes** capability with "Location updates" and "Remote notifications").
2. Dart, `courier_telemetry_service.dart`: on iOS use
   ```dart
   AppleSettings(
     accuracy: LocationAccuracy.high,
     distanceFilter: 10,
     activityType: ActivityType.otherNavigation,
     pauseLocationUpdatesAutomatically: false,
     allowBackgroundLocationUpdates: true,
     showBackgroundLocationIndicator: true, // the blue pill: the iOS version of the Android notification
   )
   ```
   Keep **When In Use** permission. With the location background mode and `allowsBackgroundLocationUpdates`, iOS keeps delivering positions after the courier locks the phone, and shows the blue location indicator. Do **not** ask for Always; Apple asks hard questions about it and it is not needed.

Do not add the `location` background mode without the code change: Guideline 2.5.4 allows background services only "for their intended purposes", and a declared mode the app does not use is a common rejection.

**Review notes for the courier app** (paste into App Review Information → Notes):

> Malvoya Courier is used by independent couriers who deliver orders from local shops. A courier taps "Go online" to receive delivery offers. While online with the app open, it uses location so that (1) offers go to the nearest couriers and (2) the server can check the courier is at the shop before pickup and calculate the pay for the ride. While an order is being delivered, the app keeps using location in the background (UIBackgroundModes: location, When In Use permission, blue indicator shown) so that (3) the customer and the shop can follow the delivery. Background use ends with the delivery; all sharing stops when the courier taps "Go offline" or signs out. Location is never used for advertising. Demo account: … (approved courier, test mode).

## 9. Push notifications

- APNs key in Firebase (section 3), Push Notifications capability, `remote-notification` background mode.
- The apps ask for notification permission with `FirebaseMessaging.instance.requestPermission()`. Ask at a moment where the user understands why (store: during setup "to hear new orders"; courier: in the go-online check; customer: after the first order). Apple rejects apps that require notifications to function (4.5.4) — the store app explains it but must still work without it.
- Store app: iOS cannot ring until answered like Android's insistent notification (G15). Consider requesting the **time-sensitive** entitlement for new-order pushes and say in onboarding "keep the app open or notifications on".

## 10. Universal Links (customer app) — backend task

The share pages `/s/:storeId`, `/r/:code` and `/d/:id` open the Android app via App Links. For iOS:

1. **Backend:** add a route next to `assetlinks.json` in `backend/src/modules/share/share.routes.ts`:
   - `GET /.well-known/apple-app-site-association` (no extension), `Content-Type: application/json`, status 200, **no redirect**, HTTPS.
   - Body (Team ID from env, e.g. `APPLE_TEAM_ID`):
     ```json
     {
       "applinks": {
         "details": [
           {
             "appIDs": ["<TEAM_ID>.com.malvoya.customer"],
             "components": [
               { "/": "/s/*", "comment": "Store share pages" },
               { "/": "/r/*", "comment": "Invite links" },
               { "/": "/d/*", "comment": "Drop share pages" }
             ]
           }
         ]
       }
     }
     ```
   - Empty `details` when `APPLE_TEAM_ID` is not set, like the Android fingerprints.
2. **App:** Associated Domains capability with `applinks:malvoya-api-eu.onrender.com` (and your own domain later). **Done 2026-10-25** in `Malvoya_customer/ios/Runner/Runner.entitlements`; `FlutterDeepLinkingEnabled` is false so only `app_links` handles the links (as on Android). The JSON above is also in `docs/ios/apple-app-site-association.example.json`. Universal Links need the paid account (the capability on the App ID).
3. Apple fetches the file through its CDN, so changes take time. For testing add `?mode=developer` to the entitlement domain (remove before release).
4. If the API moves to your own domain later, both files must be served there.

## 11. App Privacy ("nutrition labels")

App Store Connect → the app → **App Privacy**. Answers per app, matching `docs/play-data-safety.md` and the code. For every type: **Linked to the user: Yes** (it is tied to the account), **Used for tracking: No**. Malvoya has no ads, no ad SDK, no IDFA, so there is no App Tracking Transparency prompt and **"Data Used to Track You" is empty**.

Apple's rule on payment cards: payment info is out of scope only if it is entered *outside* the app and you never have access. Stripe's PaymentSheet is shown inside the app, so declare **Payment Info** for the customer app (collected by Stripe as a partner for App Functionality), even though Malvoya's servers never see the card.

**Customer — Malvoya**

| Apple data type | Purposes |
|---|---|
| Contact Info → Name | App Functionality |
| Contact Info → Email Address | App Functionality |
| Contact Info → Phone Number | App Functionality |
| Contact Info → Physical Address | App Functionality |
| Financial Info → Payment Info | App Functionality (Stripe) |
| Location → Precise Location | App Functionality (delivery pin; "notify me when it opens near me") |
| User Content → Other User Content | App Functionality (reviews, drop comments, reports) |
| User Content → Customer Support | App Functionality (support messages) |
| Identifiers → User ID | App Functionality |
| Identifiers → Device ID | App Functionality (push token / Firebase installation ID) |
| Purchases → Purchase History | App Functionality |
| Usage Data → Product Interaction | App Functionality (likes, views, follows, favourites) |
| Other Data | Stripe's device data for fraud prevention → declare under the type Stripe documents, purpose App Functionality |

Order chat is relayed and not stored; Apple counts data "collected" when it leaves the device and is retained longer than needed to serve the request, so you can leave chat out (or declare User Content → Emails or Text Messages to be safe).

**Store — Malvoya Store**

| Apple data type | Purposes |
|---|---|
| Contact Info → Name, Email Address, Phone Number, Physical Address (pickup address) | App Functionality |
| Location → Precise Location | App Functionality (one fix when placing the store) |
| User Content → Photos or Videos | App Functionality (products, drops, logo, banner) |
| User Content → Other User Content | App Functionality (product texts, drop captions, comment replies) |
| User Content → Customer Support | App Functionality |
| Identifiers → User ID, Device ID | App Functionality |
| Purchases → Purchase History (the store's sales) | App Functionality |
| Financial Info → Other Financial Info (payouts, commission, Stripe account id; bank details are typed on Stripe's web pages) | App Functionality |
| Sensitive Info: none (the DAC7 tax ID and date of birth for private sellers go under **Other Data** or **Contact Info → Other** with purpose App Functionality; Apple has no "tax ID" type) | App Functionality |

**Courier — Malvoya Courier**

| Apple data type | Purposes |
|---|---|
| Contact Info → Name, Email Address, Phone Number | App Functionality |
| Location → Precise Location and Coarse Location | App Functionality (offers, check-in, tracking, pay) |
| User Content → Photos or Videos | App Functionality (delivery photo, deleted after 30 days) |
| User Content → Customer Support | App Functionality |
| Identifiers → User ID, Device ID | App Functionality |
| Financial Info → Other Financial Info (earnings, payouts) | App Functionality |

**Privacy manifest (G14):** add `ios/Runner/PrivacyInfo.xcprivacy` to each app with `NSPrivacyTracking` = false, `NSPrivacyTrackingDomains` = [], `NSPrivacyCollectedDataTypes` matching the tables above, and `NSPrivacyAccessedAPITypes` for what the app's own code uses (for Flutter apps usually `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`). Xcode's **Product → Generate Privacy Report** (or the Codemagic build log) shows what the plugins already declare. Apple has required reasons for these APIs since 2024-05-01.

## 12. Export compliance

The apps use encryption only through HTTPS/TLS (the API, Stripe, Firebase, Cloudinary) and the platform's secure storage (`flutter_secure_storage` → Keychain). That is standard encryption used for authentication and secure connections, which is exempt from US export documentation (EAR Category 5 Part 2, mass-market / "primary function is not information security").

- Recommended answer in App Store Connect: the app uses encryption, it qualifies for the exemption, **no documentation needed**.
- Then add to each `Info.plist` so TestFlight stops asking:
  ```xml
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  ```
- France: Apple notes French controls on secure storage, secure communications and anti-virus apps. Malvoya is none of these; no French declaration is needed. If the apps ever add end-to-end encrypted chat, revisit this.

## 13. Payments (Guideline 3.1.3(e)) and marketplace review

- **Physical goods and delivery are paid with Stripe, not in-app purchase.** Guideline 3.1.3(e): "If your app enables people to purchase physical goods or services that will be consumed outside of the app, you must use purchase methods other than in-app purchase." Clothes, delivery fees and courier tips are all outside the app. This is allowed and expected.
- Do not sell anything **digital** inside the app through Stripe (for example paid boosts or a "premium" store plan bought in the store app). Digital features consumed in the app must use in-app purchase.
- Stripe PaymentSheet supports Apple Pay. Optional: register an Apple Pay **Merchant ID** and add it to `Stripe.merchantIdentifier` for one-tap payment.
- Stripe Connect onboarding (store and courier payouts) opens Stripe's web pages; that is fine (no money flows to Apple and it is not a purchase).

**Demo accounts (Guideline 2.1, the most common rejection):** Apple must be able to use every app without waiting for an approval.

- Customer: a test customer account with email + password, and at least one **approved** test store with products near a fixed test address (Apple reviews from the US; set a delivery address in Helsinki in the notes so the store list is not empty, or explain "Notify me when it opens here").
- Store: an **already approved** test store account (otherwise Apple sees only "pending approval" and rejects under 2.1).
- Courier: an **approved** courier account, plus a note on how a test job can be created (or a short screen recording of the flow linked in the notes).
- The backend must be up (Render free instances sleep: the first request can take 30–60 s, which reviewers read as "the app does not load"). Keep the API awake during review.
- Stripe is in test mode: say so and give the test card `4242 4242 4242 4242` in the notes.

**Review times:** Apple says it reviews about 50 % of submissions in under 24 hours and 90 % in under 48 hours. The first submission of a new app often takes longer, and three related apps from a new account may be looked at together. Expedited review exists for critical bug fixes and time-bound events only.

**Common rejection reasons for marketplace and delivery apps, and how Malvoya stands:**

| Reason | Guideline | Malvoya |
|---|---|---|
| Reviewer cannot sign in, gets "pending approval", empty lists, server asleep | 2.1 | Demo accounts + awake API (above) |
| Crashes or placeholder content (`[PLACEHOLDER]` in legal texts!) | 2.1 | The legal pages still contain `[PLACEHOLDERS]` (no Y-tunnus yet). Fill them before review: Apple opens the privacy policy and terms |
| Missing or vague purpose strings | 5.1.1(ii) | Fixed in this change |
| Google sign-in without an equivalent | 4.8 | Section 6 |
| No in-app account deletion | 5.1.1(v) | Done |
| Background location without a clear need | 2.5.4, 5.1.5 | Courier only, with review notes (section 8) |
| UGC without blocking | 1.2 | G10: add "Block this user" on drop comments (hides their comments for you; server-side list per user) |
| Several near-identical apps from one developer | 4.3 | Three apps for three different roles is normal for marketplaces; say so in the notes ("customer, store and courier apps of one marketplace") and make sure each app's listing and screenshots are clearly different |
| Thin app / "repackaged website" | 4.2 | Native features (map, camera, push, video) are fine |
| Using IAP for physical goods, or Stripe for digital goods | 3.1.1, 3.1.3(e) | Stripe for physical goods: correct |
| Screenshots that are not the real app | 2.3.3 | Use the screenshot kit with real screenshots |
| Seller is a person but the app looks like a company (or the reverse) | 5.1.1, 3.2 | The App Store seller name comes from your enrolment (section 1) |
| Requiring users to enable notifications or location to use the app | 4.5.4, 5.1.1 | Customer and store work without them; courier needs location only to go online, which is explained |

## 14. Order of work

1. Decide individual vs company enrolment (section 1). Enrol; accept agreements; set the EU trader status.
2. Fix G1–G3 and G12 (bundle IDs, names, iPhone only, export key). Small native edits.
3. Firebase iOS apps, APNs key, `GoogleService-Info.plist` via CI secrets (section 3).
4. Decide Option A or B for Google sign-in (section 6) and make the app and backend changes.
5. Courier background location (section 8) and the store push behaviour (G15).
6. Block users in comments (G10). Fill the legal placeholders.
7. Codemagic workflows, first TestFlight builds, internal testing on a real iPhone.
8. AASA route on the API (section 10), Associated Domains capability.
9. Screenshots from TestFlight on an iPhone, App Privacy answers, privacy manifest, age rating, listing copy, review notes with demo accounts.
10. Submit the three apps (customer first; store and courier can follow once the customer app is approved).

---

## Sources

All read on the date given.

- Apple, App Review Guidelines (1.2, 2.1, 2.3.3, 2.3.4, 2.5.4, 3.1.3(e), 4.2, 4.3, 4.8, 5.1.1): https://developer.apple.com/app-store/review/guidelines/ (2026-10-16)
- Apple, Offering account deletion in your app: https://developer.apple.com/support/offering-account-deletion-in-your-app/ (2026-10-16)
- Apple, Enrollment (individual vs organisation, D-U-N-S, 99 USD): https://developer.apple.com/programs/enroll/ (2026-10-16)
- Apple, App privacy details: https://developer.apple.com/app-store/app-privacy-details/ (2026-10-16)
- Apple, Overview of export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance (2026-10-16)
- Apple, Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications (2026-10-16)
- Apple, App preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications (2026-10-16)
- Apple, App Review (review times, common issues): https://developer.apple.com/distribute/app-review/ (2026-10-16)
- Apple, Upcoming requirements (Xcode 26 from 2026-04-28, iOS 13 minimum from 2026-09-09, age ratings, privacy manifests, EU trader status): https://developer.apple.com/news/upcoming-requirements/ (2026-10-17)
- Apple, Supporting associated domains: https://developer.apple.com/documentation/xcode/supporting-associated-domains (2026-10-16)
- Firebase, Cloud Messaging on Apple platforms (APNs key upload): https://firebase.google.com/docs/cloud-messaging/ios/client (2026-10-16)
- Firebase, Federated identity & social sign-in for Flutter (`revokeTokenWithAuthorizationCode`): https://firebase.google.com/docs/auth/flutter/federated-auth (2026-10-17)
- Codemagic pricing: https://codemagic.io/pricing/ (2026-10-16)
- `geolocator_apple` 2.3.14 source, `PermissionHandler.m` (pub cache, 2026-10-16)
