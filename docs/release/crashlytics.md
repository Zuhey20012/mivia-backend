# Crash reports with Firebase Crashlytics

This guide is for the owner. The three apps (Malvoya, Malvoya Store, Malvoya Courier) send crash reports to **Firebase Crashlytics** in the Firebase project **mivia-4f159**. The code is in place; the console only needs switching on once.

## What the apps send

| When | Report |
|---|---|
| The app crashes (Flutter or Dart error nobody caught) | **Fatal** crash with the error type, a cleaned message and the stack trace |
| The API answers 5xx, or a 2xx answer whose body is not valid JSON | **Non-fatal** `ApiFault: GET /orders/:x 503` (method, path with ids and query removed, status). 4xx answers and lost connections are never reported |

Each report carries only:

- custom keys `app_version` (for example `1.8.0+10`) and `role` (`customer`, `store` or `courier`);
- the **numeric Malvoya user id** as the user identifier, set after sign-in and cleared on sign-out;
- what Crashlytics adds itself: device model, OS version, free memory, a random installation id.

Never names, emails, phone numbers, addresses, tokens or request bodies. Error texts are scrubbed before they leave the phone (`packages/malvoya_core/lib/src/crash/crash_scrubber.dart`), and Flutter's widget context (which can contain on-screen text) is left out.

Reports are sent only from **release builds** (signed builds from `mobile-android.yml` / `mobile-ios.yml`, Google Play, TestFlight). Debug builds, including the unsigned debug APK the Android workflow makes without the keystore secrets, switch collection off and only print to the console. On iPhone, a build without `GoogleService-Info.plist` does not start Crashlytics at all.

## 1. Switch Crashlytics on (once)

1. Open https://console.firebase.google.com and choose the project **mivia-4f159**.
2. In the left menu: **Run → Crashlytics** (or search "Crashlytics" at the top).
3. If it asks, pick each app (`com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier`, and the iOS apps once they exist) and click **Enable Crashlytics**.
4. The page then waits for the first report ("Waiting for your app to crash…"). Install a **release** build of each app (section 1 of `docs/release/README.md`), open it once, close it, and open it again: Crashlytics sends reports on the next start. The dashboard appears within a few minutes after the first report.

Nothing else is needed for Android: `google-services.json` is already in each app, and the Gradle plugin `com.google.firebase.crashlytics` is applied next to `com.google.gms.google-services`.

### iPhone (on the Mac, when the iOS apps are set up)

- `GoogleService-Info.plist` must be in the build (the iOS workflow adds it from its secret). Without it, Crashlytics stays off.
- After adding the package, run `cd ios && pod install` once on the Mac so `Podfile.lock` gets the Crashlytics pod.
- Optional, for readable native (Swift/Objective-C) crashes: in Xcode → Runner target → **Build Phases** → add a Run Script `"${PODS_ROOT}/FirebaseCrashlytics/run"` with the input file `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}`, and set **Debug Information Format** to **DWARF with dSYM File** for Release. Dart stack traces are readable without it.

## 2. Read the reports

Firebase console → **mivia-4f159** → **Crashlytics**, then choose the app at the top.

- **Issues list:** each row is one problem, grouped by where in the code it happened, with the number of events and of affected users. **Crash-free users** at the top is the share of people who had no crash.
- Filter with **Event type**: *Crashes* (fatal) or *Non-fatals* (the `ApiFault` reports and other handled errors). A burst of `ApiFault … 5xx` usually means the API had a problem: check Render's logs for `malvoya-api-eu` at the same time.
- Open an issue to see the **stack trace** (the top lines in `package:malvoya_…` point at the file and line), the **Keys** tab (`app_version`, `role`) and **Data** (device, OS).
- **Find one person's crashes:** search the issues by **User ID** with their numeric Malvoya id (admin panel → user). Only do this to help that person, for example after a support request.
- An issue fixed in a new build: open it and click **Close issue**. If it happens again in a newer version, Crashlytics reopens it as a regression.
- Optional: switch on Crashlytics **email alerts** (new issues, regressions, sudden spikes) in the console's alert settings for the project.

## 3. Privacy

- Purpose: fixing faults. Legal basis: legitimate interest. Retention: Firebase deletes reports after **90 days**. This is written in `legal/privacy_policy.md` (section 2, "Crash reports") and in the Play Data safety answers (`docs/play-data-safety.md`, "Crash logs and diagnostics").
- Do not copy reports out of Firebase into other tools, and do not add custom keys, logs or user details beyond what the code sends. The code only allows the keys `app_version` and `role`; changing that needs a privacy-policy update first.
- To stop collection entirely, set `enabled: false` in the `CrashReporting.instance.init(...)` call in each app's `lib/main.dart` (it is `kReleaseMode` by default) and publish new builds; the apps then switch Crashlytics off on the phone.
