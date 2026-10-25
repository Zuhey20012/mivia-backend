# Running the Malvoya apps on an iPhone simulator (MacBook Air)

This guide is for running the three apps (**Malvoya**, **Malvoya Store**, **Malvoya Courier**) on the iPhone simulator on your Mac, without being a developer. Do the steps in order. Commands go into the **Terminal** app (press ⌘ Space, type `Terminal`, press Return), one line at a time: paste a line, press Return, wait until it finishes.

What you need: a MacBook Air with Apple silicon (M1 or newer) and macOS 15 (Sequoia) or newer, about 60 GB of free disk space, your Apple ID, and an internet connection. Nothing in this guide costs money.

---

## 1. Install Xcode and its command line tools

1. Open the **App Store** on the Mac, search for **Xcode**, click **Get** / **Install**. It is large (about 15 GB); it can take an hour.
2. Open **Xcode** once from the Applications folder. Accept the licence. When it asks which platforms to install, tick **iOS** (this downloads the iPhone simulator). If it does not ask, do it later in step 1.4.
3. In Terminal, run these three lines (the `sudo` lines ask for your Mac password; nothing is shown while you type it, that is normal):
   ```bash
   xcode-select --install
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```
   If the first line says the tools are "already installed", that is fine.
4. Make sure the iPhone simulator is installed:
   ```bash
   xcodebuild -downloadPlatform iOS
   ```

Apple requires **Xcode 26 or newer** for App Store uploads (since 2026-04-28). The App Store version of Xcode is new enough.

## 2. Install Homebrew, CocoaPods and Flutter

1. **Homebrew** (an installer for developer tools). Paste this one line and follow what it prints:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
   At the end it prints two or three lines under "Next steps" that start with `echo` / `eval`. Copy and run them, then close Terminal and open it again.
2. **CocoaPods** (fetches the iOS parts of the plugins) and **git**:
   ```bash
   brew install cocoapods git
   pod --version
   ```
   The last line should print a version such as `1.16.2`.
3. **Flutter**, the same version the apps are built with on Windows: **Flutter 3.41.2, channel stable (Dart 3.11.0)**. The apps' `pubspec.yaml` asks for Dart `>=3.4.0 <4.0.0`; 3.41.2 is what they are tested with.
   ```bash
   mkdir -p ~/development
   git clone https://github.com/flutter/flutter.git -b 3.41.2 ~/development/flutter
   echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   flutter --version
   flutter doctor
   ```
   `flutter --version` should say `Flutter 3.41.2 • channel stable` (it may say "detached HEAD" or no channel: that is fine). In `flutter doctor`, the **Xcode** line must be green. Android lines can stay red; you do not need Android Studio on the Mac.

## 3. Get the code

```bash
cd ~/development
git clone https://github.com/Zuhey20012/mivia-backend.git
cd mivia-backend
git checkout birch-market
```

The folder `~/development/mivia-backend` now contains `Malvoya_customer`, `malvoya_vendor`, `malvoya_courier` and the shared `packages` folder. The apps find `packages` through relative paths (`../packages/...`), so keep the folders side by side as they are.

## 4. Prepare the customer app

```bash
cd ~/development/mivia-backend/Malvoya_customer
flutter pub get
cd ios
pod install
```

`pod install` takes a few minutes the first time and ends with "Pod installation complete!". It creates `ios/Pods/` (never commit it) and `ios/Podfile.lock` (commit it later, so every build uses the same versions).

## 5. Open the project in Xcode

```bash
open Runner.xcworkspace
```

Always open **Runner.xcworkspace** (white icon), never `Runner.xcodeproj`: the project file alone does not see the pods and fails with "No such module".

## 6. Sign in with your Apple ID and choose "Personal Team"

1. In Xcode: **Xcode → Settings… → Accounts**, click **+**, choose **Apple ID**, sign in. Your account appears with a team called "**Your Name (Personal Team)**". This is free.
2. Close Settings. In the left column click **Runner** (the blue icon at the top), then the **Runner** target under TARGETS, then the **Signing & Capabilities** tab.
3. Tick **Automatically manage signing** and choose **Your Name (Personal Team)** under **Team**. The **Bundle Identifier** shows `com.malvoya.customer`.

Xcode may show a red message such as *"Personal development teams … do not support the Push Notifications, Sign In with Apple and Associated Domains capabilities"*. That is expected with a free account and **does not matter for the simulator**: simulator builds are not signed with a profile. It only matters on a real iPhone (see section 13).

## 7. Run on an iPhone simulator

1. At the top of the Xcode window, next to "Runner", click the device name and choose **iPhone 17** (or **iPhone 16**; any iPhone in the "iOS Simulators" list works).
2. Press the **▶ Run** button (or ⌘ R). The first build takes 5–10 minutes; later ones are quicker. The Simulator window opens and Malvoya starts.

Or, from Terminal (does the same and shows the app's log):
```bash
cd ~/development/mivia-backend/Malvoya_customer
open -a Simulator
flutter devices
flutter run -d "iPhone 17"
```
`flutter devices` lists the simulators by name; use one of those names. `flutter run -d ios` also works when only one simulator is open. Press `q` in Terminal to stop the app.

Without `GoogleService-Info.plist` (section 9) the app works with email + password, email codes and browsing; there are no pushes, no phone codes through Firebase (the server sends them instead), no Google and no Apple button. That is on purpose: the app hides what cannot work instead of crashing.

## 8. The store and courier apps

The same steps, in their own folders:

```bash
cd ~/development/mivia-backend/malvoya_vendor
flutter pub get
cd ios && pod install && open Runner.xcworkspace
```

```bash
cd ~/development/mivia-backend/malvoya_courier
flutter pub get
cd ios && pod install && open Runner.xcworkspace
```

In each, choose your Personal Team (section 6) and press ▶ Run. Bundle identifiers: `com.malvoya.vendor` (Malvoya Store) and `com.malvoya.courier` (Malvoya Courier). On iPhone the store and courier apps have no "Continue with Google" button: Apple's rule 4.8 would otherwise require Sign in with Apple as well. Email + password and the phone code remain.

The courier app keeps sharing its location with the screen locked **only while an order is being delivered** (the blue location pill shows at the top of the screen). Between jobs it shares location only while it is open. In the simulator choose **Features → Location → City Run** (or **Custom Location…**) to give it a moving position.

## 9. Adding GoogleService-Info.plist later (Firebase: push, phone and Apple sign-in)

Do this once per app, when you want those features.

1. Open https://console.firebase.google.com → the Malvoya project → **Project settings** (gear) → **Your apps** → **Add app → iOS**.
2. Apple bundle ID: `com.malvoya.customer` (then repeat for `com.malvoya.vendor` and `com.malvoya.courier`). Nickname: Malvoya iOS. Skip the "Add Firebase SDK" steps.
3. Download **GoogleService-Info.plist**.
4. In Xcode, with that app's `Runner.xcworkspace` open: drag the file from Finder onto the yellow **Runner** folder in the left column. In the dialog tick **Copy items if needed** and the **Runner** target, click **Finish**. It must end up as `ios/Runner/GoogleService-Info.plist`.
   - The file is listed in `.gitignore` and must **not** be committed (the GitHub repository is public).
5. Phone sign-in on iOS also needs Firebase's callback address. In the Firebase console, on the same iOS app, copy the **Encoded App ID** (it looks like `app-1-123456789012-ios-abc123def456`). Open `ios/Flutter/Malvoya.xcconfig` in TextEdit (or in Xcode) and replace the value after `FIREBASE_ENCODED_APP_ID =` with it.
6. **Customer app only, Google sign-in:** open `GoogleService-Info.plist` in Xcode and copy two values into `ios/Flutter/Malvoya.xcconfig`:
   - `CLIENT_ID` → after `GOOGLE_IOS_CLIENT_ID =`
   - `REVERSED_CLIENT_ID` → after `GOOGLE_REVERSED_CLIENT_ID =`
   - and after `GOOGLE_SERVER_CLIENT_ID =` the **Web client ID** the server uses (the backend's `GOOGLE_CLIENT_ID` on Render, also `default_web_client_id` in Android's `google-services.json`). With it, Google's token is addressed to the server, which then accepts it.
   If the plist has no `CLIENT_ID`, enable **Google** under Firebase → Authentication → Sign-in method first and download the plist again.
7. **Customer app only, Sign in with Apple:** Firebase console → **Authentication → Sign-in method → Apple → Enable**. The button then appears on iPhone. In the simulator, first sign in to an Apple ID in the simulator's **Settings** app.
8. Press ▶ Run again (a "Clean Build Folder", ⇧⌘K, first does no harm).

These values are not secret (they are inside every installed app), but keep `GoogleService-Info.plist` out of git anyway.

## 10. Testing a push notification in the simulator (free)

The simulator on an Apple-silicon Mac accepts test pushes without any Apple account (Xcode 14 or newer):

1. Run the app in the simulator and allow notifications when it asks (the apps ask at a moment where it makes sense, for example the courier app in the go-online check). If you said no, allow them in the simulator's **Settings → Notifications → the app**.
2. Press ⇧⌘H to go to the simulator's home screen.
3. Drag one of these files from Finder onto the simulator window:
   - `docs/ios/push-customer.apns` (Malvoya)
   - `docs/ios/push-store.apns` (Malvoya Store)
   - `docs/ios/push-courier.apns` (Malvoya Courier)

   Each file names its app (`"Simulator Target Bundle"`), so the banner appears for the right one. From Terminal the same is:
   ```bash
   xcrun simctl push booted com.malvoya.customer ~/development/mivia-backend/docs/ios/push-customer.apns
   ```

Real pushes from the Malvoya server (Firebase Cloud Messaging → Apple's push service) need the paid Apple Developer account: an **APNs key** (Apple Developer → Keys) uploaded in Firebase → Project settings → Cloud Messaging. See `docs/app-store-release-checklist.md`, section 3.

## 11. Recording a video and taking App Store screenshots

**Video** (for a demo or an App Store preview). With the app running in the simulator:
```bash
cd ~/Desktop
xcrun simctl io booted recordVideo demo.mov
```
Use the app; press **Control C** in Terminal to stop. `demo.mov` is on your Desktop. (The Simulator menu **File → Record Screen** does the same.)

**Screenshots:** in the Simulator press **⌘ S** (saved to the Desktop), or:
```bash
xcrun simctl io booted screenshot ~/Desktop/home.png
```

Sizes the App Store wants (from `docs/app-store-release-checklist.md`, section 5): the **iPhone 6.1"** size is required, **1206 × 2622** or **1179 × 2556** pixels, portrait.
- An **iPhone 17** simulator saves screenshots at 1206 × 2622.
- An **iPhone 16** simulator saves screenshots at 1179 × 2556.

Screenshots straight from the simulator have exactly these sizes, so no resizing is needed. iPad screenshots are not needed: the apps are iPhone-only. Before taking them, set the clock to 9:41 and a full battery: `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100`. Frame them with `docs/store-assets/screenshot-kit/`.

## 12. Common errors and fixes

| What you see | What to do |
|---|---|
| `pod: command not found` / "CocoaPods not installed" | `brew install cocoapods`, then close and reopen Terminal. If `brew` is not found either, redo section 2.1 including the "Next steps" lines. |
| `CocoaPods could not find compatible versions for pod "Firebase/..."` or "... is out of date" | `cd ios && pod repo update && pod install` (or `pod install --repo-update`). If it still fails: `rm -rf Pods Podfile.lock && pod install --repo-update`. |
| `Generated.xcconfig must exist` when running `pod install` | Run `flutter pub get` in the app folder first (one level above `ios`). |
| "The iOS deployment target ... is set to 12.0, but the range of supported deployment target versions is …", or "requires a minimum of iOS 15" | The apps need **iOS 15.0** or newer; the Podfile already sets it for every pod. Run `pod install` again after `flutter pub get`, and choose a simulator with iOS 15 or newer (all current ones are). Do not lower `platform :ios, '15.0'` in `ios/Podfile`. |
| A box saying "To open … you need to install Rosetta" | Click **Install**, or run `softwareupdate --install-rosetta --agree-to-license`. Some simulator tools still use it on Apple silicon. |
| "No signing certificate 'iOS Development' found" / "Signing for 'Runner' requires a development team" | Section 6: sign in under Xcode → Settings → Accounts and choose your Personal Team. Then **Product → Clean Build Folder** (⇧⌘K) and Run. The simulator itself needs no certificate; with `flutter run -d "iPhone 17"` you never see this. |
| "Personal development teams … do not support Push Notifications / Sign In with Apple / Associated Domains" | Expected with a free account. Ignore it for the simulator. For a real iPhone see section 13. |
| "No such module 'Flutter'" or "Module 'firebase_core' not found" | You opened `Runner.xcodeproj`. Close it and open `Runner.xcworkspace`. If it persists: `flutter clean && flutter pub get && cd ios && pod install`. |
| "Unable to boot the Simulator" / no iPhones in the device list | `xcodebuild -downloadPlatform iOS`, then restart the Mac. |
| `flutter doctor` says "Xcode installation is incomplete" | `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch` |
| The app opens and stays on a white or purple screen, or says it cannot reach the server | The API on Render sleeps when unused; the first request can take up to a minute. Wait and pull to refresh. |

When something else goes wrong: `flutter clean`, `flutter pub get`, `cd ios && pod install`, then Run again. Copy the red error text when asking for help.

## 13. What needs the paid Apple Developer account (99 USD a year)

The free Personal Team is enough for everything above on the **simulator**. You need the paid membership (https://developer.apple.com/programs/enroll/, see the checklist section 1 for individual vs company) for:

- **A real iPhone for longer than 7 days.** With a free account an app installed on your own iPhone stops opening after 7 days, and the free team cannot sign push, Sign in with Apple or Universal Links. To try it on your iPhone anyway, change `CODE_SIGN_ENTITLEMENTS` in `ios/Flutter/Malvoya.xcconfig` to `Runner/RunnerPersonalTeam.entitlements` (those three features are then off) and change it back afterwards. Note that Xcode then registers `com.malvoya.…` to your free team; if Apple later says the identifier "is not available" in your paid account, use a temporary bundle ID such as `com.yourname.malvoya.test` for free-account device tests.
- **Push notifications on a real device** (APNs key in Firebase).
- **Sign in with Apple and Universal Links on a real device** (capabilities on the App ID; the server must publish the Apple file, see the checklist section 10).
- **TestFlight** (testers install the app from Apple) and **App Store** submission.

## 14. Without the Mac: Codemagic

Codemagic builds iOS apps on its own Macs (500 free build minutes a month). The complete setup, including a `codemagic.yaml` with one workflow per app, is in `docs/app-store-release-checklist.md`, section 2. Two Malvoya-specific additions for those workflows:

1. Store each app's `GoogleService-Info.plist` as a base64 secret and write it to `ios/Runner/GoogleService-Info.plist` in a script step (shown in the checklist).
2. Put the values of section 9 (steps 5–6) into `ios/Flutter/Malvoya.xcconfig` before the build, either by committing them (they are not secret) or with a script step, for example:
   ```bash
   sed -i '' "s|^FIREBASE_ENCODED_APP_ID = .*|FIREBASE_ENCODED_APP_ID = $FIREBASE_ENCODED_APP_ID_CUSTOMER|" ios/Flutter/Malvoya.xcconfig
   ```

Codemagic needs the paid Apple account too (an App Store Connect API key), but no Mac.
