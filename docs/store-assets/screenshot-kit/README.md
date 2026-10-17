# Screenshot kit

`index.html` frames **real** screenshots of the apps for Google Play and the App Store: a caption band at the top (the captions from `docs/play-store-listing.md`, EN or FI), a brand-colour background, and your screenshot below it. It runs entirely in your browser; nothing is uploaded.

Never put a mock-up, an edited screen or someone else's data in a store screenshot. Google requires screenshots that "show the actual app experience", and Apple rejects inaccurate screenshots (Guideline 2.3.3).

## 1. Prepare the phone

- Install a **release** build (the same one you upload), in **light mode**, language set to the listing language (Finnish for the FI set).
- Use only test data you made yourself: your own test stores, your own product photos, a test order to a public place (for example a library or a station), no real names, phone numbers or home addresses, no brand logos you do not own, no reviews or ratings you wrote yourself.
- Tidy the status bar: full battery, Wi-Fi on, no notifications. On Android you can use the System UI demo mode (Developer options → System UI demo mode), or with adb:

  ```text
  adb shell settings put global sysui_demo_allowed 1
  adb shell am broadcast -a com.android.systemui.demo -e command enter
  adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200
  adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
  adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
  ```

  Turn it off afterwards: `adb shell am broadcast -a com.android.systemui.demo -e command exit`.

## 2. Take the screenshots

Take one screenshot per row of the plan (six per app, the screens are listed in each slot of the kit).

**Android phone, no computer:** press power + volume down. The files are in Photos/Gallery → Screenshots. Send them to the PC (USB cable, Google Drive or Quick Share).

**Android over USB (adb):** use `screencap` on the phone and then `adb pull`. In PowerShell, do **not** use `adb exec-out screencap -p > shot.png`: PowerShell's `>` rewrites the bytes as text and the PNG becomes unreadable (this is what happened to `Malvoya_customer/emulator_screenshot.png`).

```text
adb shell screencap -p /sdcard/malvoya-01.png
adb pull /sdcard/malvoya-01.png .
adb shell rm /sdcard/malvoya-01.png
```

(`adb exec-out screencap -p > shot.png` is fine in Git Bash or `cmd.exe`.)

**iPhone (for the App Store set):** press side button + volume up, then AirDrop or iCloud the files to the PC. You need a TestFlight build on a real iPhone (see `docs/app-store-release-checklist.md`). A 6.1" iPhone with Dynamic Island gives 1179 × 2556 and a 6.3" one gives 1206 × 2622; both are the sizes Apple requires, so you can upload them as they are or frame them here. Android screenshots must not be used for the App Store (they show Android system UI).

## 3. Frame them

1. Open `docs/store-assets/screenshot-kit/index.html` in Chrome or Edge (double-click works).
2. Pick the app, the language and the size:
   - **Google Play phone 1080 × 1920**: 2–8 screenshots, 9:16. Keep **Frame: Screenshot only**; Google asks for no device frames.
   - **App Store iPhone 6.1" 1206 × 2622**: required. 6.9" (1320 × 2868 or 1290 × 2796) is optional, 5.5" (1242 × 2208) is optional and no longer required. iPad 13" (2064 × 2752) is needed only while the iOS project still allows iPad (it does today, see the checklist).
3. Drag a screenshot onto a slot, or several at once onto slot 1 (they fill the slots in file-name order: name them `01.png`, `02.png`…).
4. Check or edit the caption (keep it short and factual: no "best", "#1", prices or ratings), pick a background.
5. **Download** (one) or **Download all**. Files are JPEG (`customer-fi-play-01.jpg`), because PNGs exported by a browser always carry an alpha channel, which both stores reject.

Upload in the same order as the plan. Play: Store presence → Main store listing → Phone screenshots (and again under Manage translations → Finnish). App Store Connect: the app version → Previews and Screenshots → iPhone, per language.

## Feature graphic with a real screenshot

`docs/store-assets/feature-graphic.html` renders the 1024 × 500 Play feature graphic. The PNGs in `docs/store-assets/<app>/feature-graphic-{en,fi}.png` show the app's real launch screen in the phone. When you have the real screen the brief asks for (Drops for the customer app, Orders for Store, an offer for Courier), copy it into `docs/store-assets/<app>/screens/` and render again:

```text
"C:\Program Files\Google\Chrome\Application\chrome.exe" --headless --hide-scrollbars --window-size=1024,500 --screenshot=C:\Users\Zuhey\mivia\docs\store-assets\customer\feature-graphic-en.png "file:///C:/Users/Zuhey/mivia/docs/store-assets/feature-graphic.html?app=customer&lang=en&shot=customer/screens/drops.png"
```

Use `app=store|courier` and `lang=fi` for the others. Chrome writes a 24-bit PNG without alpha (checked 2026-10-17), which is what Play asks for. Upload the FI graphic under Manage translations → Finnish.

## Sources (read 2026-10-16)

- Google Play preview assets (screenshots 2–8, 320–3840 px, 9:16, no alpha, no device frames, feature graphic 1024 × 500): https://support.google.com/googleplay/android-developer/answer/9866151
- Apple screenshot specifications (6.1" required, 6.9"/6.5" and 5.5" optional, iPad 13" if the app runs on iPad, no alpha, up to 10): https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- App Review Guidelines 2.3.3 / 2.3.4: https://developer.apple.com/app-store/review/guidelines/
