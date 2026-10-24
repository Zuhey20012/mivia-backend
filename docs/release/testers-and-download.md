# Getting the apps onto phones: testers, downloads and the Play 14-day test

## 1. Three ways to install, from quickest to official

| Way | Who | How | Limits |
|---|---|---|---|
| **APK file** (now) | you and a few trusted people | send `Malvoya_APKs\1_Malvoya_Customer_v1.x.apk` and the others; on the phone allow "Install unknown apps" for the file app, then open the APK | Android only; no automatic updates; Google Play Protect may warn about an unknown app (normal for test files) |
| **Play internal testing** (as soon as the Play account exists) | up to 100 testers you add by email | Play Console → app → Testing → Internal testing → upload the `.aab` → add testers' Gmail addresses → copy the opt-in link | available in minutes, no review |
| **Play closed testing** (required before production for a personal account) | **at least 12 testers, opted in for 14 days in a row, per app** | Testing → Closed testing → create a track → upload the `.aab` → add a Google Group or email list → share the opt-in link | Google reviews the first closed release (usually hours to a few days) |

After 14 days with 12+ opted-in testers: Play Console → Dashboard → **Apply for production access**. Google asks a few questions about the test: how testers used the app, what feedback you got, and what you changed. Answer honestly; the notes from section 4 below are your evidence.

## 2. Your step list (Google Play)

1. Create the Google Play developer account (play.google.com/console, personal, 25 USD, identity check).
2. Create three apps: "Malvoya", "Malvoya Store", "Malvoya Courier" (package names `com.malvoya.customer`, `com.malvoya.vendor`, `com.malvoya.courier`).
3. Complete the store listing (text in `docs/play-store-listing.md`, graphics in `docs/store-assets/`), Data safety (`docs/play-data-safety.md`), content rating, target audience and the account-deletion URL (`https://malvoya-api-eu.onrender.com/legal/delete-account`).
4. App integrity: let Google manage the app signing key. Copy the **SHA-256** shown and add it to `ANDROID_APP_SHA256` on Render (comma after the existing value), and add it to Firebase (`docs/blueprint/malvoya-product-blueprint.md` §6).
5. Upload the `.aab` files from `Desktop\Malvoya_Apps` to Internal testing first, then to Closed testing.
6. Start the 14 days for all three apps on the same day.

## 3. The invitation to testers (copy and send)

**Suomeksi**
> Hei! Rakennan Malvoyaa, sovellusta, jolla lähiseudun muoti- ja kauneusliikkeiden tuotteet saa kotiin samana päivänä tai noudettua kaupasta. Tarvitsen 12 testaajaa, joilla on Android-puhelin, 14 päivän ajaksi. Testaaminen on ilmaista, eikä oikeita maksuja tehdä (käytämme testikortteja).
> 1. Liity tällä linkillä: [opt-in-linkki]
> 2. Asenna Malvoya Google Playsta samalla Google-tilillä.
> 3. Pidä sovellus puhelimessa 14 päivää ja avaa se muutaman kerran viikossa.
> 4. Kerro minulle, mikä oli helppoa ja mikä hankalaa. Kuvakaappaukset ovat kullanarvoisia!
> Kiitos paljon! 💛

**In English**
> Hi! I'm building Malvoya, an app to get fashion and beauty from local shops delivered the same day or ready to pick up. I need 12 testers with an Android phone for 14 days. It's free and no real payments are made (we use test cards).
> 1. Join with this link: [opt-in link]
> 2. Install Malvoya from Google Play with the same Google account.
> 3. Keep the app for 14 days and open it a few times a week.
> 4. Tell me what was easy and what was hard. Screenshots are gold!
> Thank you so much! 💛

For the Store and Courier apps, ask a few testers to install those too, to try shop set-up and courier sign-up. The test environment uses Stripe **test mode**; give testers the card `4242 4242 4242 4242`, any future date and any CVC. It is Stripe's public test card, and no real money moves.

## 4. What to ask testers (copy into a form or chat)
1. Find a product in a category you like and add it to the bag. Was anything confusing?
2. Complete a test order with the test card. What would stop you buying for real?
3. Try "Forgot password" and the language switch.
4. Rate 1–5: speed, look, ease. What one thing would you change?

Keep the answers. Google's production-access form asks what you learned, and your next sprint fixes the top 3 issues.

## 5. Apple (when the iPhone builds are ready)
TestFlight replaces the 14-day rule: internal testers (up to 100 people on your team) get builds immediately; external testers (up to 10 000) need a short Beta review. Steps are in `docs/ios/MAC-SETUP.md` and `docs/app-store-release-checklist.md`.

## 6. The download page
The website (`web/`, page `/lataa` and `/en/download`) shows "Coming soon" badges until the store links exist. When each app is live, replace the placeholder links with the real Play and App Store URLs and redeploy the site.
