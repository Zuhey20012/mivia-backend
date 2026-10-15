# Google Play: permissions, disclosures and declarations

Checked on 2026-10-15 against the source manifests and the **merged** release manifests that Gradle builds
(`<app>/build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`).
Plugins add permissions you never typed, so the merged manifest is what Google sees.

All three apps: `minSdk 24`, `targetSdk 36` (Flutter 3.41.2, AGP 8.11.1). Google Play needs **API 36** for new apps and updates from 31 August 2026, so this is fine.

Quick answer for the Play Console forms:

| Play Console form | Customer | Store | Courier |
|---|---|---|---|
| Foreground service permissions | not needed | not needed (see note under Store) | **needed: location** |
| Location permissions (background) | not needed | not needed | not needed (no `ACCESS_BACKGROUND_LOCATION`) |
| Photo and video permissions | not needed (no `READ_MEDIA_*`) | not needed | not needed |
| Advertising ID | **No** (no `AD_ID` permission, no ads SDK) | No | No |
| Prominent disclosure in the app | not needed once the unused location permission is removed | short note recommended | **dialog missing — must add** |

---

## 1. Customer app (`com.malvoya.customer`)

Source manifest: `Malvoya_customer/android/app/src/main/AndroidManifest.xml`.

| Permission | Where it comes from | Why it is there, in plain words | Disclosure in the app |
|---|---|---|---|
| `INTERNET` | manifest line 2 | Talk to the Malvoya API, Stripe, Cloudinary and map tiles. | Not needed (normal permission). |
| `ACCESS_FINE_LOCATION` | manifest line 3 | **Not used.** The app has no location plugin (`geolocator` is not in `pubspec.yaml`) and never asks for location. Addresses are typed or pinned on the map by hand. | None. |
| `ACCESS_COARSE_LOCATION` | manifest line 4 | **Not used**, same as above. | None. |
| `POST_NOTIFICATIONS` | manifest line 5 | Show order, delivery and drop notifications (Android 13+ asks the user). | Asked straight after sign-in with no explanation: `Malvoya_customer/lib/core/push_service.dart:95`. Allowed by policy, but see the tip below. |
| `VIBRATE` | manifest line 6 | Vibrate for local notifications. | Not needed. |
| `ACCESS_NETWORK_STATE` | added by `connectivity_plus` / Firebase | Show the "you are offline" banner. | Not needed. |
| `WAKE_LOCK`, `com.google.android.c2dm.permission.RECEIVE`, `READ_GSERVICES` | added by Firebase Messaging / Play services | Receive push messages. | Not needed. |
| `com.malvoya.customer.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | added by AndroidX | Internal Android plumbing. | Not needed. |

**What to fix**

1. **Remove the two location permissions** from `Malvoya_customer/android/app/src/main/AndroidManifest.xml` (lines 3–4). They are never used. Keeping them makes the store page say the app can access location, and invites reviewer questions. (This doc does not change app code; the owner or the app agent must do it.)
2. Optional, good practice: ask for notifications at a moment that makes sense (after the first order, "Get updates about your order?") instead of straight after sign-in. Android's own guidance says not to prompt at launch.

Play Console declarations needed: none for permissions.

---

## 2. Store app (`com.malvoya.vendor`)

Source manifest: `malvoya_vendor/android/app/src/main/AndroidManifest.xml`.

| Permission | Where it comes from | Why it is there | Disclosure in the app |
|---|---|---|---|
| `INTERNET` | line 2 | API, uploads to Cloudinary. | Not needed. |
| `POST_NOTIFICATIONS` | line 3 | New-order alarm and order reminders. **Important for the store**: without it, the shop misses orders, which are refunded after 10 minutes. | Asked after sign-in with no explanation: `malvoya_vendor/lib/core/push_service.dart:108`. |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | lines 4–5 | One-time GPS fix when the seller taps **"Use my current location"** to put the pickup point on the map (`malvoya_vendor/lib/screens/store_setup.dart:96-118`, button at `:253-259`). Not tracked afterwards. | The button label is the only context: `store_setup.dart:258` — "Use my current location" / "Käytä nykyistä sijaintia". If refused: `store_setup.dart:105` — "Location permission is needed to put your store on the map." Hint at `:143`. |
| `ACCESS_NETWORK_STATE`, `VIBRATE`, `WAKE_LOCK`, c2dm, `READ_GSERVICES`, `DYNAMIC_RECEIVER_…` | plugins | Same as customer. | Not needed. |

**Camera, photos, videos, files:** no `CAMERA`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` or storage permission is in the merged manifest.
- Photos and videos come through `image_picker` (`product_editor.dart:106`, `:137`; `create_drop.dart:60-63`; `store_setup.dart:121`). On Android 13+ that opens the system **Photo Picker**. "Take a photo / Record a video" hands over to the phone's own camera app, which needs no permission while `CAMERA` is not declared.
- The CSV import uses `file_picker` (`import_products_screen.dart:169`), which opens the system file chooser. No permission.
- So the **Photo and video permissions** declaration does not apply. Keep it that way: never add `READ_MEDIA_*`.

**Note on a foreground service you did not add:** the `geolocator` plugin puts a `GeolocatorLocationService` with `foregroundServiceType="location"` into the merged manifest (line ~115). The store app never starts it and does not hold `FOREGROUND_SERVICE_LOCATION`, so Play should not ask for a foreground-service declaration. If Play Console *does* ask, either answer "not used" or remove the service from the store app's manifest with `tools:node="remove"`.

**Recommended (not strictly required):** a one-line note under the location button, e.g.
"Used once to put your pickup point on the map. Your location is not tracked." /
"Käytetään kerran noutopisteen merkitsemiseen kartalle. Sijaintiasi ei seurata."
This is a foreground, user-started request, so a full prominent-disclosure dialog is not required.

Play Console declarations needed: none for permissions.

---

## 3. Courier app (`com.malvoya.courier`)

Source manifest: `malvoya_courier/android/app/src/main/AndroidManifest.xml`.

| Permission | Where it comes from | Why it is there | Disclosure in the app |
|---|---|---|---|
| `FOREGROUND_SERVICE` | line 2 | Run a visible service while the courier is online. | — |
| `FOREGROUND_SERVICE_LOCATION` | line 3 | That service reads GPS. Android 14+ needs this type. **Needs a Play Console declaration (below).** | See "Prominent disclosure" below. |
| `POST_NOTIFICATIONS` | line 4 | Job offers, plus the "online" notification. | Asked after sign-in: `malvoya_courier/lib/core/push_service.dart:95`. |
| `INTERNET` | line 5 | API and socket. | — |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | lines 6–7 | Precise position while online: rank job offers by distance, check "too far" and "at the shop", calculate ride pay, show the courier to the customer and store of the order being carried, record the handover position. | See below. |
| `WAKE_LOCK` | line 8 | Keep GPS running with the screen off (`enableWakeLock: true`, `courier_telemetry_service.dart:50`). | — |
| `ACCESS_NETWORK_STATE`, `VIBRATE`, c2dm, `READ_GSERVICES`, `DYNAMIC_RECEIVER_…` | plugins | — | — |

No `ACCESS_BACKGROUND_LOCATION`. Good: that would need a separate, much harder declaration.

**Camera / photos:** the door-drop photo uses `ImagePicker().pickImage(source: ImageSource.camera)` (`courier_dashboard.dart:683`), which opens the phone's camera app. No `CAMERA` permission is declared, so none is needed. The instruction shown before the photo (`courier_dashboard.dart:671-672`): "Photograph only the parcel at the door — no people, faces or house numbers. Only the customer sees it; it is deleted after 30 days."

### How location works today (from the code)

1. The courier taps **Go online** (`courier_dashboard.dart:1216-1220`) or the switch on the online card (`:1008`).
2. `CourierTelemetryService.start()` asks for location permission (`courier_telemetry_service.dart:35-37`) and starts `Geolocator.getPositionStream` with a foreground notification (`:41-53`).
3. Notification text (`courier_telemetry_service.dart:47-48`), **English only**:
   "Malvoya Courier is online" / "Your location is shared while you are online. Go offline to stop."
4. Going offline calls `stop()` (`courier_dashboard.dart:213`) and the server deletes the stored position. Sign-out also stops it.
5. **When the app opens and the server still says the courier is online, sharing restarts without a tap** (`courier_dashboard.dart:161-163`). If permission was revoked, the system prompt appears with no explanation first.

### Disclosure text that exists

- Offline screen, right above the Go online button (`courier_dashboard.dart:1210-1211`):
  "Go online to get job offers near you. Your location is shared only while you are online." /
  "Mene linjoille saadaksesi keikkatarjouksia lähelläsi. Sijaintisi jaetaan vain, kun olet linjoilla."
- Online card (`courier_dashboard.dart:996-998`):
  online: "Location is shared only while you are online; a notification shows while it is shared."
  offline: "Your location is not shared while you are offline."
- After refusal (`courier_dashboard.dart:203`): "Turn on location and allow it for Malvoya Courier to go online."
- Going offline mid-delivery (`courier_dashboard.dart:234`): explains that sharing stops and the customer can no longer follow the delivery.

### What is missing (must fix before submitting)

Google's User Data policy says a runtime permission request "must be immediately preceded by an in-app disclosure" that says what data is collected, how it is used and shared, and needs an explicit tap to accept. The location policy says that when a foreground service keeps reading location after the user leaves the app and it amounts to background access, the background-location disclosure rules apply. Those rules need the word "location", one of the phrases "background", "when the app is closed", "always in use" or "when the app is not in use", and every feature that uses it.

The current one-line hint does not say **who** sees the location (the customer and the store), does not say it keeps running **in the background with the screen off**, and is not a consent dialog. The automatic restart in `_init()` also skips it.

**Add a dialog** before the first call to `Geolocator.requestPermission()`, and whenever permission is not granted. Show it from the Go online button and the switch. Do not restart sharing in `_init()` without it. Suggested text:

> **Share your location while you are online**
> Malvoya Courier collects your precise location while you are online, including when the app is in the background or your screen is off. It is used to offer you delivery jobs near you, check that you are at the store, calculate your pay for the ride to the store, and show your position to the customer and the store of the order you are delivering. A notification shows the whole time. Sharing stops when you go offline. Malvoya keeps only your latest position and deletes it when you go offline; the position where you hand over an order is kept with that order for 30 days as proof of delivery. Your location is not used for ads.
> [Not now] [Continue]

> **Sijaintisi jaetaan, kun olet linjoilla**
> Malvoya Courier kerää tarkan sijaintisi, kun olet linjoilla, myös silloin kun sovellus on taustalla tai näyttö on pois päältä. Sijaintia käytetään lähellä olevien keikkojen tarjoamiseen, sen tarkistamiseen, että olet kaupalla, kauppaan ajon palkkion laskemiseen ja sijaintisi näyttämiseen toimittamasi tilauksen asiakkaalle ja kaupalle. Ilmoitus näkyy koko ajan. Jakaminen loppuu, kun poistut linjoilta. Malvoya säilyttää vain viimeisimmän sijaintisi ja poistaa sen, kun poistut linjoilta; luovutuspaikan sijainti säilytetään tilauksen yhteydessä 30 päivää toimituksen todisteena. Sijaintia ei käytetä mainontaan.
> [Ei nyt] [Jatka]

Also: translate the foreground notification (`courier_telemetry_service.dart:47-48`) to Finnish, or show both languages, and put the same paragraph in the courier app's store description (Play asks for location use to be described in the listing too).

### Play Console declaration: foreground service (copy and paste)

Where: Play Console → the courier app → **Policy and programs → App content → Foreground service permissions** (Google's help calls the area "Monitor and improve → App content"; the menu name changes from time to time).

- **Foreground service type:** Location (`FOREGROUND_SERVICE_LOCATION`)
- **Use case:** *User-initiated location sharing* (the courier turns sharing on with "Go online" and off with "Go offline"). If a reviewer pushes back, *Navigation* ("ride tracking for a ride-share app") is the second-closest option, because the customer follows the courier on a map.
- **Description of the feature:**

  > Malvoya Courier is the app for independent couriers who deliver local fashion orders in Finland. A courier taps "Go online" to start receiving delivery jobs. While online, the app runs a location foreground service with a permanent notification ("Malvoya Courier is online"). It sends the courier's position to our server so that (1) new jobs are offered to the nearest couriers, (2) the server can confirm the courier is at the store before pickup and calculate the pay for the ride to the store, and (3) the customer and the store of the order being delivered can follow the courier on a map until handover. Couriers carry the phone in a pocket or bike mount with the screen off, so a foreground service is needed. The service starts only after the courier taps "Go online" and stops as soon as they tap "Go offline" or sign out; the server then deletes the stored position. We do not request background location permission.

- **User impact if the task is deferred or interrupted:**

  > If the system pauses or delays the service, the customer's live map freezes and they cannot see where their order is; the server sees the courier's position as unknown after 2 minutes, so the courier cannot accept nearby jobs or check in at the store, and the waiting and ride pay cannot be calculated. A delivery in progress can then not be tracked until the courier opens the app again.

- **Video link:** an unlisted YouTube video (30–90 s) recorded on a real phone with a test courier account. Show, in order:
  1. The courier app on the Jobs tab, offline.
  2. Tapping **Go online** → the new disclosure dialog → **Continue** → the Android permission prompt → "While using the app".
  3. The "Malvoya Courier is online" notification in the status bar.
  4. Pressing Home and turning the screen off; then the customer app (second phone or screen recording) still showing the courier moving on the order map.
  5. Back in the courier app, tapping **Go offline** → the notification disappears.

  Record after the disclosure dialog is added. A video of the current build would show a permission prompt with no explanation in front of it.

### Content rating note

The courier's location is shared with other users (the customer and the store of the order). Answer "yes" to the IARC question about sharing a user's location with other users for the courier app. For the customer app, answer "no" once the unused location permission is removed.

---

## 4. Notification permission (all apps)

`POST_NOTIFICATIONS` is a runtime permission on Android 13+. No Play Console declaration exists for it. The apps ask right after sign-in (`push_service.dart`). Android's guidance is to ask in context, not at launch. Suggested rationale lines, shown in a small sheet before the system prompt:

- Customer: "Get a message when your order is accepted, on its way and delivered." / "Saat viestin, kun tilauksesi on hyväksytty, matkalla ja toimitettu."
- Store: "New orders ring until you answer. Without notifications you may miss orders, and unanswered orders are refunded after 10 minutes." / "Uudet tilaukset hälyttävät, kunnes vastaat. Ilman ilmoituksia voit menettää tilauksia: vastaamattomat tilaukset hyvitetään 10 minuutin kuluttua."
- Courier: "Hear about new delivery jobs near you while you are online." / "Kuulet uusista keikoista lähelläsi, kun olet linjoilla."

---

## Sources

- Target API level (API 36 from 31 Aug 2026, extension to 1 Nov 2026): https://support.google.com/googleplay/android-developer/answer/11926878 and https://developer.android.com/google/play/requirements/target-sdk (read 2026-10-15; page dated 2026-10-01)
- Foreground service declaration (description, user impact, video, use case; location use cases): https://support.google.com/googleplay/android-developer/answer/13392821 (read 2026-10-15)
- Location permissions policy (prominent disclosure, FGS treated as background): https://support.google.com/googleplay/android-developer/answer/9799150 (read 2026-10-15)
- User Data policy, prominent disclosure and consent: https://support.google.com/googleplay/android-developer/answer/10144311 (read 2026-10-15)
- Photo and video permissions policy (full compliance since 28 May 2025): https://support.google.com/googleplay/android-developer/answer/14115180 (read 2026-10-15)
- Notification permission: https://developer.android.com/develop/ui/views/notifications/notification-permission (read 2026-10-15)
