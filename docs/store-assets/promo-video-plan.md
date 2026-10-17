# Promo video plan

One short video per app, cut from **real screen recordings** of release builds with your own test data. No hands, no people, no actors, no stock footage, no mock screens, no claims ("best", "#1", "thousands of…"), no money amounts presented as earnings promises.

Two cuts of each video:

| Cut | Where | Source recordings | Length |
|---|---|---|---|
| **Play / YouTube** | Google Play "Preview video" (a YouTube URL) | Android phone | 25 s |
| **App Store app preview** | App Store Connect → Previews and Screenshots | **iPhone** (Android footage cannot be used: it shows Android system UI) | 25 s (Apple allows 15–30 s) |

Both cuts use the same storyboard so you only plan once.

---

## 1. Rules (checked 2026-10-16)

### Google Play preview video
- Added as a **YouTube URL** in Store presence → Main store listing → Preview video (per language under Manage translations).
- The YouTube video must be **public or unlisted** (not private), **ads turned off**, **not age-restricted**, and **embeddable**. Use the plain video URL, not a playlist, channel or a link with a timecode.
- Only the **first 30 seconds autoplay**, so the important part goes first.
- Landscape or portrait is allowed. For portrait, do not leave black bars on the sides (export at 1080 × 1920).
- Source: https://support.google.com/googleplay/android-developer/answer/9866151 (read 2026-10-16).

### App Store app preview
- **15–30 seconds**, up to **3 previews per device size and language**.
- iPhone large sizes (6.9" / 6.7" / 6.5"): **886 × 1920 portrait** (or 1920 × 886 landscape). iPad 13": 1200 × 1600. Check the spec page for any other size you upload.
- H.264 (`.mov`, `.m4v`, `.mp4`) or ProRes 422 HQ (`.mov`), **max 30 fps**, max **500 MB**.
- The poster frame defaults to 5 s in; choose a clear frame (the home or offer screen).
- Guideline 2.3.4: "previews may only use video screen captures of the app itself." You may add narration and text overlays. So: no hands holding a phone, no device frames, no people, no brand end cards made outside the app. End on a real app screen with a text overlay instead.
- Previews autoplay **muted** on the App Store: the captions must carry the message without sound.
- Sources: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications and https://developer.apple.com/app-store/review/guidelines/#previews (both read 2026-10-16).

---

## 2. How to record

Prepare the phone as in `screenshot-kit/README.md` (release build, light mode, Finnish or English, demo-mode status bar, your own test stores and products, a test order to a public place). Record each shot separately; 5–10 seconds of slow, deliberate taps per shot is plenty.

**Android, from the phone:** pull down Quick Settings → **Screen record** (Android 11+). Choose "no audio" and "show touches: off". Files land in Photos → Movies.

**Android, over USB:**
```text
adb shell screenrecord --bit-rate 12000000 --time-limit 20 /sdcard/shot-01.mp4
adb pull /sdcard/shot-01.mp4 .
adb shell rm /sdcard/shot-01.mp4
```
`screenrecord` records at the screen's resolution, stops at `--time-limit` seconds (max 180) or Ctrl+C, and records no sound.

**iPhone:** Settings → Control Centre → add **Screen Recording**, then start it from Control Centre (microphone off). Move the files to the PC with AirDrop or iCloud Photos (choose "Download and keep originals").

**Editing (free):** Clipchamp (built into Windows 11), DaVinci Resolve, or Shotcut. Project 1080 × 1920, 30 fps. Export H.264 MP4. For the App Store cut, export **886 × 1920, 30 fps** (scale the 1080 × 1920 timeline down; Apple rejects other sizes).

**Captions:** Bricolage Grotesque 700 for the caption, Hanken Grotesk for the small line, from `docs/store-assets/shared/` (install the TTFs from any app's `assets/fonts/` on the PC). Birch `#F6F3EE` text on a brand-colour band at the top, or ink `#1C1820` on Birch. Keep captions on screen at least 2 seconds and inside the top 20 % so they do not cover the UI.

**Music:** optional (App Store previews start muted). Use only a track whose licence covers app-store marketing, not just YouTube. The YouTube Audio Library is fine for the YouTube/Play cut only if the track's licence allows it; for the App Store cut buy a licence or use no music. No voice-over is needed.

**Privacy check before export:** no real person's name, phone, address or face; no real card numbers (do not record the card entry; cut from the price breakdown straight to "Paid"); no test card numbers on screen; no notifications from other apps.

---

## 3. Customer app — Malvoya (25 s)

Music mood: warm, light, unhurried (acoustic or soft indie pop, about 100 BPM).

| # | Time | Record this (real screen) | Caption EN | Caption FI |
|---|---|---|---|---|
| 1 | 0:00–0:04 | App opens (launch screen) → Home with nearby test stores, "open now" visible; slow scroll | Local stores, near you | Lähikaupat, lähelläsi |
| 2 | 0:04–0:09 | Drops tab: a test store's video plays, swipe to the next drop | Drops from local shops | Dropit lähikaupoista |
| 3 | 0:09–0:14 | Product page: swipe the gallery, pick a size, add to bag | See it before you buy | Katso ennen kuin ostat |
| 4 | 0:14–0:18 | Checkout: delivery or pickup choice, the full price breakdown (items, delivery fee) | The whole price, up front | Koko hinta etukäteen |
| 5 | 0:18–0:23 | Order tracking: the courier's position moving on the map (a real test order, second phone running the courier app) | Follow your courier | Seuraa lähettiä |
| 6 | 0:23–0:25 | Back on Home (real screen) with overlay | Malvoya · Local fashion, from shops near you | Malvoya · Muotia lähikaupoista |

Play/YouTube cut only: shot 6 may instead be a 2-second end card with the app icon and the same line (`docs/store-assets/customer/play-icon-512.png` on Birch).

## 4. Store app — Malvoya Store (25 s)

Music mood: steady, confident, unfussy (lo-fi house or warm electronic, about 100 BPM).

| # | Time | Record this (real screen) | Caption EN | Caption FI |
|---|---|---|---|---|
| 1 | 0:00–0:05 | Orders tab: a paid test order arrives and rings; tap Accept | Never miss an order | Älä missaa tilausta |
| 2 | 0:05–0:10 | Product editor: add photos, a size option and stock, save | Products in minutes | Tuotteet hetkessä |
| 3 | 0:10–0:15 | Create drop: pick a video, write a caption, link a product, post | Post drops to local shoppers | Julkaise dropeja lähiasiakkaille |
| 4 | 0:15–0:19 | Import screen: Shopify / CSV options (do not show third-party shop names you do not own) | Bring your catalogue | Tuo valikoimasi |
| 5 | 0:19–0:23 | Store tab: opening hours, then flip the pause switch | Open when you are | Auki, kun sinä olet |
| 6 | 0:23–0:25 | Orders tab (real screen) with overlay | Malvoya Store · Sell to shoppers near you | Malvoya Store · Myy lähellä oleville |

Do not show payout amounts or commission figures. They are test values and could read as a promise.

## 5. Courier app — Malvoya Courier (25 s)

Music mood: upbeat but calm, a riding rhythm (light indie or downtempo, about 110 BPM).

| # | Time | Record this (real screen) | Caption EN | Caption FI |
|---|---|---|---|---|
| 1 | 0:00–0:04 | Offline screen with the location note → tap "Go online" → the location disclosure → online | Go online when it suits you | Linjoille, kun sinulle sopii |
| 2 | 0:04–0:10 | A job offer arrives; open "How is this pay calculated?" | See the pay before you accept | Näet palkkion ennen hyväksymistä |
| 3 | 0:10–0:15 | Delivery tab, step by step: to the store, check in, pick up | Every step, clearly | Jokainen vaihe selkeästi |
| 4 | 0:15–0:19 | Handover sheet: in person / photo at the door (photograph a parcel at a public place, no house numbers) | Hand over with care | Luovuta huolella |
| 5 | 0:19–0:23 | Earnings tab, scroll | Your earnings in one place | Ansiosi yhdessä paikassa |
| 6 | 0:23–0:25 | Go offline (real screen) with overlay | Malvoya Courier · Location only while online | Malvoya Courier · Sijainti vain linjoilla |

Shot 2 shows a pay figure from a test order. Add a small second line "Example from a test order" / "Esimerkki testitilauksesta" while it is on screen, and do not zoom in on the amount. Never add text such as "earn up to…".

---

## 6. Upload checklist

- [ ] Recorded on a release build with test data only; privacy check done.
- [ ] Play cut: 1080 × 1920 H.264, ≤ 30 s, uploaded to YouTube as **unlisted**, ads off, not age-restricted, embedding on; URL pasted in Play (EN and FI listings can use different videos).
- [ ] App Store cut: recorded on an iPhone, 886 × 1920, ≤ 30 fps, 15–30 s, H.264, ≤ 500 MB; no non-app footage; poster frame chosen; uploaded per language.
- [ ] Music licence covers the platform, or no music.
