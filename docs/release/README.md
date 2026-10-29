# Building and sending the Malvoya apps with GitHub Actions

This guide is for the owner, step by step. GitHub builds the three apps on its own computers, so you need neither Android Studio nor a Mac to make a build:

| Workflow (Actions tab) | File | Builds |
|---|---|---|
| **Mobile - Android** | `.github/workflows/mobile-android.yml` | APK (and AAB for Google Play) for Malvoya, Malvoya Store, Malvoya Courier; can send them to testers with Firebase App Distribution |
| **Mobile - iOS** | `.github/workflows/mobile-ios.yml` | App Store `.ipa` for the three apps; can upload to TestFlight |

Both start by hand (Actions → Run workflow) or when you push a tag that starts with `mobile-v` (section 8).

**You can run them today, with no secrets at all.** Then:

- **Android** builds a *debug* APK of each app. It installs on any Android phone and talks to the live test API, but it is not for Google Play (section 3.4 explains the limits).
- **iOS** only checks that the apps compile. The file it keeps (`…-ios-UNSIGNED-not-installable`) **cannot be installed** on an iPhone. Real iPhone builds need the paid Apple Developer account (section 6).

Everything below adds the missing pieces one at a time. Each secret is optional; a workflow that misses one says so in its run summary and skips that part.

---

## 1. Run a workflow and download the builds

1. Open https://github.com/Zuhey20012/mivia-backend and click **Actions**.
2. In the left column, choose **Mobile - Android** (or **Mobile - iOS**).
3. Click **Run workflow** (right side). Choose:
   - **Use workflow from**: the branch to build (normally `master`).
   - **Which apps to build**: `all`, `customer`, `store` or `courier`.
   - Android: **distribute** (tick to send to Firebase testers), **release notes** (what testers should try), **tester groups** (leave empty for the default).
   - iOS: **testflight** (tick to upload to TestFlight).
4. Click the green **Run workflow**. A new run appears after a few seconds. Android takes about 10–15 minutes, iOS about 20–40.
5. Open the finished run. The **Summary** page says, per app, what was built (signed or debug), whether it went to testers, and lists the files under **Artifacts** at the bottom. Click a name to download a `.zip`; the APK/AAB/IPA is inside.

Notes:
- You must be signed in to GitHub to download artifacts. They are deleted after **14 days**; run the workflow again for a fresh one.
- File names carry the app, version and build number, for example `malvoya-customer-1.8.0-build10-release.apk`.
- A red run: open the failed app's job; the first red line (`Error: …`) says what to fix, for example a missing `google-services.json` or a secret with a wrong password.

---

## 2. Adding a GitHub secret

Secrets are passwords and keys that the workflows can use but nobody can read back, not even you.

1. Repository page → **Settings** → **Secrets and variables** → **Actions**.
2. **New repository secret**. **Name**: exactly as written in the tables below (capital letters, underscores). **Secret**: the value. **Add secret**.
3. To change one later, click its name → **Update**.

The repository is **public**: never put these values in a file in the repository, an issue or a comment. Only people with write access to the repository can start these workflows, and secrets are never given to pull requests from forks.

Many secrets are files turned into text ("base64"). How to make that text:

- **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\file")) | Set-Clipboard
  ```
  The text is now on the clipboard; paste it as the secret value.
- **Mac (Terminal):** `base64 -i /path/to/file | pbcopy`

### All secret names

| Secret | Needed for | Section |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | signed Android release (APK + AAB) | 3 |
| `ANDROID_KEYSTORE_PASSWORD` | signed Android release | 3 |
| `ANDROID_KEY_ALIAS` | signed Android release | 3 |
| `ANDROID_KEY_PASSWORD` | signed Android release | 3 |
| `FIREBASE_DISTRIBUTION_SA` | sending APKs to testers | 4 |
| `FIREBASE_ANDROID_APP_ID_CUSTOMER`, `FIREBASE_ANDROID_APP_ID_STORE`, `FIREBASE_ANDROID_APP_ID_COURIER` | optional: only if the app ids differ from those in `android/app/google-services.json` (the workflow reads them from there) | 4 |
| `FIREBASE_TESTER_GROUPS` | optional: tester group alias(es), comma separated; default `testers` | 4 |
| `APPLE_TEAM_ID` | signed iOS build | 6 |
| `IOS_DIST_CERT_P12_BASE64` | signed iOS build | 6 |
| `IOS_DIST_CERT_PASSWORD` | signed iOS build | 6 |
| `IOS_PROVISIONING_PROFILE_CUSTOMER_BASE64`, `IOS_PROVISIONING_PROFILE_STORE_BASE64`, `IOS_PROVISIONING_PROFILE_COURIER_BASE64` | signed iOS build of that app | 6 |
| `APPSTORE_CONNECT_API_KEY_ID` | TestFlight upload | 6 |
| `APPSTORE_CONNECT_ISSUER_ID` | TestFlight upload | 6 |
| `APPSTORE_CONNECT_API_KEY_P8_BASE64` | TestFlight upload | 6 |
| `GOOGLESERVICE_INFO_PLIST_CUSTOMER_BASE64`, `GOOGLESERVICE_INFO_PLIST_STORE_BASE64`, `GOOGLESERVICE_INFO_PLIST_COURIER_BASE64` | push, phone, Google and Apple sign-in on iPhone | 6.7 |

The four Android signing secrets go together: set all four or none. The same holds for the four iOS signing secrets of an app (`APPLE_TEAM_ID`, the certificate, its password, that app's profile). A half-filled set stops the run with a message that names what is missing.

---

## 3. Android: the upload key

Google Play needs every `.aab` signed with your **upload key**. Google then re-signs the app for phones with its own key (Play App Signing), so if the upload key is ever lost, Google support can reset it; still, look after it.

### 3.1 Do you already have one?

The `.aab` files in `Desktop\Malvoya_Apps` were built with a keystore named in each app's `android\key.properties` on your Windows PC. **If you have already uploaded any of them to Play Console, use that same keystore** (skip to 3.3). Make a new one only if nothing was uploaded yet.

### 3.2 Create the upload keystore (once, for all three apps)

`keytool` comes with Java; with Android Studio installed it is at `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`. In PowerShell:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore "$HOME\malvoya-upload-keystore.jks" -storetype PKCS12 `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

(On a Mac: `keytool -genkeypair -v -keystore ~/malvoya-upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.)

It asks for a password (choose a long one) and for your name and organisation. Your own name and `FI` as the country are fine; do not invent a company name. With a PKCS12 keystore the key password is the same as the keystore password.

### 3.3 Keep it safe

- Store the `.jks` file **and** its password in a password manager (for example as an attachment), plus one offline copy (USB stick kept at home).
- Never put the `.jks` file or the password in the repository, in email or in chat. `*.jks` and `key.properties` are git-ignored, but a copy in another folder would not be.

### 3.4 Add the four secrets

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the `.jks` file as base64 (section 2) |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `upload` (or the alias in your existing `key.properties`) |
| `ANDROID_KEY_PASSWORD` | the key password (the same as the keystore password for a PKCS12 keystore) |

From then on every Android run builds a **signed release APK** (for testers) and an **AAB** (for Google Play). The run checks the password and alias before building and stops with a clear message if they do not open the keystore.

Without these secrets the run builds **debug APKs** instead. Their limits: slower than release, not accepted by Google Play, signed with a throw-away key that changes every run (a tester uninstalls the previous build before installing a new one), and Google sign-in does not work in them (Firebase does not know that key). Email sign-in, browsing and test payments work.

### 3.5 Tell Firebase about the upload key (for Google and phone sign-in in tester builds)

Builds signed with the upload key need its fingerprints in Firebase:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "$HOME\malvoya-upload-keystore.jks" -alias upload
```

Copy the **SHA1** and **SHA256** lines. Firebase console → project **mivia-4f159** → Project settings → Your apps → each Android app (`com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier`) → **Add fingerprint** (both). Builds installed from Google Play are signed with Google's key instead; add that SHA-256 as well when Play shows it (see `docs/release/testers-and-download.md`, step 4).

---

## 4. Firebase App Distribution (private tester builds for Android)

App Distribution emails your testers a link, and they install through Firebase's **App Tester** app. Only invited people can download. This is the recommended way to test privately (GitHub Release files, section 8, are public).

### 4.1 Turn it on and create the tester group

1. https://console.firebase.google.com → project **mivia-4f159** (the Malvoya project) → left menu **Release & Monitor → App Distribution** → **Get started**. Do it for each of the three Android apps (choose the app in the drop-down at the top).
2. **Testers & Groups** tab → **Add group**. Name: `Testers`. Check that its **alias** is `testers` (shown under the name; the workflow uses the alias).
3. Add your testers' email addresses to the group. They get an invitation the first time a build is sent to them.

To use another group, put its alias in the run's **tester groups** box, or set the secret `FIREBASE_TESTER_GROUPS` (for example `testers,shops`).

### 4.2 Create the service account (the robot that uploads)

1. https://console.cloud.google.com → choose project **mivia-4f159** at the top.
2. **IAM & Admin → Service accounts → Create service account**. Name: `github-app-distribution`. **Create and continue**.
3. Role: **Firebase App Distribution Admin**. **Continue → Done**. (No other role is needed.)
4. Click the new account → **Keys → Add key → Create new key → JSON → Create**. A `.json` file downloads.
5. Open it in Notepad, copy **all** of it, and save it as the GitHub secret `FIREBASE_DISTRIBUTION_SA` (base64 also works). Then **delete the downloaded file** (and empty the recycle bin). If it ever leaks, delete the key on the same Keys page and make a new one.

### 4.3 Send a build

Actions → **Mobile - Android** → Run workflow → tick **distribute**, write release notes → Run. On a `mobile-v…` tag it always tries to distribute. The run summary says "sent to group(s) testers", or why it was skipped.

The Firebase app ids are read from each app's `android/app/google-services.json` (they are not secret). Set `FIREBASE_ANDROID_APP_ID_CUSTOMER` / `_STORE` / `_COURIER` only if you move the apps to another Firebase project without updating those files.

---

## 5. Google Play: internal testing (the next step)

Needs the Google Play developer account (25 USD, identity check). The full plan, including the 12-tester / 14-day rule for personal accounts, is in [`testers-and-download.md`](testers-and-download.md).

1. Make sure the four Android signing secrets are set (section 3), then run **Mobile - Android** for `all`.
2. Download each app's artifact; inside is `malvoya-<app>-<version>-build<N>-release.aab`.
3. Play Console → the app → **Testing → Internal testing → Create new release** → upload the `.aab` → release notes → **Save → Review release → Start rollout**.
4. **Testers** tab: add an email list, copy the opt-in link and send it.

Play refuses an `.aab` whose build number it has already seen: bump the version first (section 7).

---

## 6. iPhone: Apple Developer Program, certificates and TestFlight

**Nothing in this section can be done until the paid Apple Developer membership is active.** Until then the iOS workflow only checks that the apps compile.

### 6.1 Enrol

https://developer.apple.com/programs/enroll/ — **99 USD a year (charged in euros in Finland)**, one membership for all three apps. Details in [`docs/app-store-release-checklist.md`](../app-store-release-checklist.md), section 1:

- **Organisation** (for example an Oy): needs a **D-U-N-S number** (free from Dun & Bradstreet, needs a Y-tunnus first), a work email on the company's domain and a public website. The company name is shown as the seller.
- **Individual** (also a toiminimi): no D-U-N-S; your personal name is shown as the seller.
- Malvoya has no Y-tunnus yet, so today only individual enrolment is possible. Apple may take a few days to approve.

Then: App Store Connect → **Agreements, Tax and Banking** → accept the Free Apps agreement.

### 6.2 Team ID → `APPLE_TEAM_ID`

https://developer.apple.com/account → **Membership details** → **Team ID** (10 characters). Save it as `APPLE_TEAM_ID`.

### 6.3 Register the three bundle IDs

developer.apple.com → **Certificates, Identifiers & Profiles → Identifiers → +** → App IDs → App:

| Description | Bundle ID (Explicit) | Capabilities to tick |
|---|---|---|
| Malvoya | `com.malvoya.customer` | Push Notifications, Sign In with Apple, Associated Domains |
| Malvoya Store | `com.malvoya.vendor` | Push Notifications |
| Malvoya Courier | `com.malvoya.courier` | Push Notifications |

These must match the apps' entitlements, or the signed build fails.

### 6.4 Create the app records in App Store Connect

https://appstoreconnect.apple.com → **Apps → + → New App**, three times: platform iOS; names **Malvoya**, **Malvoya Store**, **Malvoya Courier**; primary language Finnish; bundle ID from the list above; SKU for example `malvoya-customer`, `malvoya-store`, `malvoya-courier`; full access. TestFlight uploads go into these records.

### 6.5 Distribution certificate → `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`

One **Apple Distribution** certificate signs all three apps (valid one year; renew it and the profiles before it expires).

**With a Mac:** Keychain Access → Certificate Assistant → *Request a Certificate From a Certificate Authority* (save to disk) → developer.apple.com → Certificates → **+** → **Apple Distribution** → upload the request → download → double-click it. In Keychain Access → *My Certificates*, right-click "Apple Distribution: …" → **Export** → `.p12` with a password.

**Without a Mac** (Windows with Git Bash or WSL, which include `openssl`):

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout malvoya-dist.key -out malvoya-dist.csr \
  -subj "/emailAddress=YOUR_APPLE_ID_EMAIL/CN=Malvoya Distribution/C=FI"
# upload malvoya-dist.csr at developer.apple.com -> Certificates -> + -> Apple Distribution,
# download the certificate (distribution.cer), then:
openssl x509 -inform DER -in distribution.cer -out malvoya-dist.pem
openssl pkcs12 -export -legacy -inkey malvoya-dist.key -in malvoya-dist.pem -out malvoya-dist.p12 -name "Apple Distribution"
```

It asks for an export password. (`-legacy` keeps the file readable by macOS; drop it if your openssl is older than 3 and says the option is unknown.)

Secrets: the `.p12` as base64 → `IOS_DIST_CERT_P12_BASE64`; its password → `IOS_DIST_CERT_PASSWORD`. Keep the `.p12`, the `.key` and the password in your password manager, like the Android keystore.

### 6.6 Provisioning profiles → `IOS_PROVISIONING_PROFILE_<APP>_BASE64`

developer.apple.com → **Profiles → +** → under Distribution choose **App Store Connect** → choose the App ID → the distribution certificate → name it (for example `Malvoya Customer App Store`) → **Generate → Download**. Three times:

| App | Secret |
|---|---|
| `com.malvoya.customer` | `IOS_PROVISIONING_PROFILE_CUSTOMER_BASE64` |
| `com.malvoya.vendor` | `IOS_PROVISIONING_PROFILE_STORE_BASE64` |
| `com.malvoya.courier` | `IOS_PROVISIONING_PROFILE_COURIER_BASE64` |

Each value is the downloaded `.mobileprovision` file as base64. The workflow checks that the profile matches the app and the team, and that it is an App Store profile (not Development or Ad Hoc). Regenerate a profile whenever you change the App ID's capabilities or renew the certificate.

### 6.7 GoogleService-Info.plist → `GOOGLESERVICE_INFO_PLIST_<APP>_BASE64`

Push notifications, Firebase phone sign-in, Google and Apple sign-in on iPhone need each app's `GoogleService-Info.plist` from Firebase (how to get it: [`docs/ios/MAC-SETUP.md`](../ios/MAC-SETUP.md), section 9, steps 1–3). It is not committed. Save each file as base64 in `GOOGLESERVICE_INFO_PLIST_CUSTOMER_BASE64`, `…_STORE_BASE64`, `…_COURIER_BASE64`.

The workflow then adds it to the build and fills `FIREBASE_ENCODED_APP_ID` (and, for the customer app, the Google client ids) in `ios/Flutter/Malvoya.xcconfig` for that build only, so you do not need to edit that file by hand. Without the plist the app still builds and works with email sign-in, but hides those features on iPhone.

Real pushes also need an **APNs key** uploaded in Firebase (`docs/app-store-release-checklist.md`, section 3); that is set in Firebase, not in GitHub.

### 6.8 App Store Connect API key (for TestFlight uploads)

App Store Connect → **Users and Access → Integrations → App Store Connect API → Team Keys → +** (the first time, *Request Access*). Name `GitHub`, access **App Manager** → **Generate**.

| Secret | Value |
|---|---|
| `APPSTORE_CONNECT_API_KEY_ID` | the **Key ID** shown in the list |
| `APPSTORE_CONNECT_ISSUER_ID` | the **Issuer ID** shown above the list |
| `APPSTORE_CONNECT_API_KEY_P8_BASE64` | the downloaded `AuthKey_XXXXXXXXXX.p8` as base64 (Apple lets you download it **only once**) |

### 6.9 Build and send to TestFlight

Actions → **Mobile - iOS** → Run workflow → tick **testflight** → Run. On a `mobile-v…` tag it uploads automatically. After the upload Apple processes the build (usually 5–30 minutes); it then appears in App Store Connect → the app → **TestFlight**. Add internal testers there (up to 100 people in your team, no review); external testers need a short Beta App Review. The export-compliance question is already answered by the apps' `Info.plist`.

Apple refuses a second upload with the same version and build number: bump the version first (section 7).

---

## 7. Version and build number

Each app's `pubspec.yaml` has a line like:

```yaml
version: 1.8.0+10
```

`1.8.0` is the version people see; `10` is the build number. **Every upload to Google Play or TestFlight needs a higher build number than the last one**, and the server's app gate (`MIN_BUILD_*`) compares build numbers too. Before a new release, change all three apps, for example to `1.8.1+11` (bug fixes) or `1.9.0+11` (new features). Keep the three apps on the same number so it stays simple.

---

## 8. Tagged releases and the GitHub Release page

To build everything at once and keep a record:

```bash
git tag mobile-v1.8.0
git push origin mobile-v1.8.0
```

(Use the version from `pubspec.yaml`; the run warns if they differ.) This starts both workflows for all three apps, sends Android builds to Firebase testers and iOS builds to TestFlight when those secrets are set, and creates a **GitHub Release** named "Malvoya apps mobile-v1.8.0" with the three **Android APKs** attached (not the AABs, not iOS files). If the upload key was not set, the attached APKs are debug builds and the release is marked *pre-release*.

**The repository is public, so the files on a GitHub Release can be downloaded by anyone on the internet.** That is fine for a test build that uses Stripe test mode, but for testing with a chosen group use Firebase App Distribution (section 4) and TestFlight instead. Delete a release on its page (Releases → the release → delete) if it should not stay public; the tag can be deleted with `git push origin :refs/tags/mobile-v1.8.0`.

---

## 9. What can and cannot be done yet

| Step | Needs | Possible today? |
|---|---|---|
| Debug APKs of all three apps | nothing | **Yes**: run Mobile - Android |
| iOS compile check | nothing | **Yes**: run Mobile - iOS (not installable) |
| Signed Android APK + AAB | upload keystore (section 3) | Yes, once you make or locate the keystore |
| Android tester builds by email | Firebase service account + tester group (section 4) | Yes, the Firebase project exists |
| Google Play internal / closed testing | Google Play developer account | No, until the Play account exists |
| Installable iPhone build, TestFlight | Apple Developer membership (section 6) | No, until Apple approves the membership |
| Organisation accounts (company as the seller) | Y-tunnus, then D-U-N-S | No, until the company exists |

---

## 10. Flutter version and troubleshooting

- The workflows use **Flutter 3.41.2** (stable), the same as `ci.yml` and the version you build with on your own computer. To change it, edit `FLUTTER_VERSION` at the top of both workflow files (and `ci.yml`).
- **"google-services.json is missing"**: download it from Firebase → Project settings → Your apps → the Android app, put it in that app's `android/app/` and commit it (it holds no secrets).
- **"keystore could not be opened"**: the password or alias secret does not match the keystore. Check them with the `keytool -list` command in section 3.5.
- **iOS "No profiles for …" / "doesn't include signing certificate"**: the profile was made with another certificate; regenerate the profile with the current distribution certificate (section 6.6).
- **iOS "provisioning profile doesn't support the … capability"**: tick the capability on the App ID (section 6.3), regenerate the profile, update the secret.
- **TestFlight "bundle version must be higher"**: bump the build number (section 7).
