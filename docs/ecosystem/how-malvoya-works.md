# How Malvoya works: the whole ecosystem

Written 26 Oct 2026 from the code that is live (API 2.12.0) and the 1.8.0 apps. "Setting" means a value the owner can change on Render or in the admin panel without new code.

---

## 1. The four parts

| Part | Who uses it | What it does |
|---|---|---|
| **Malvoya** (customer app, Android; iPhone ready to build) | shoppers | browse local fashion and beauty by category and audience, watch Drops, buy, get it delivered today or reserve & collect, track, chat with the courier, return, review |
| **Malvoya Store** (merchant app) | shop owners and staff | set up the shop, add products (by hand or by import), accept orders, hand over to couriers or pickup customers, handle returns, see statements and payouts |
| **Malvoya Courier** | couriers | go online, accept job offers with the pay shown up front, collect, deliver, get paid |
| **Admin panel** (web) | the Malvoya team | approve shops and couriers, watch orders, payouts and refunds, moderate content, verify certificates, run recalls, publish legal changes, see analytics and the System checklist |
| **Website** (malvoya-web.onrender.com) | everyone | explains the service to shoppers, shops and couriers; help centre; download links |

---

## 2. A purchase, step by step, and how the money moves

```
Customer pays 47,65 €  ──►  Stripe (Malvoya's account)  ──►  held
                                                    │
         ┌──────────────────────────────────────────┼─────────────────────────────┐
   courier transfer after delivery        shop transfer 15 days after delivery    Malvoya keeps
   (job pay + 100 % of tips)              (items − commission; held while a        commission +
                                           return is open)                         delivery fee −
                                                                                   courier pay −
                                                                                   Stripe fees
```

1. **Quote.** Before paying, the app asks the server for the exact total: items, delivery fee by distance, any service or small-order fee, promo, tip. The customer sees every euro before tapping Pay (consumer law requires this).
2. **Payment.** The customer pays in **Stripe's payment sheet** inside the app. The card number goes straight from the phone to Stripe; Malvoya's servers never see or store card data, which is the strongest PCI-DSS position a marketplace can have. Strong Customer Authentication (3-D Secure, the bank's confirmation) runs automatically when the bank asks for it.
3. **Confirmation.** An order counts as paid **only** when Stripe sends Malvoya a cryptographically signed confirmation (a webhook). A faked "paid" message from a phone can't create a paid order.
4. **Stock** is reserved when the checkout starts and released automatically after 30 minutes if payment isn't finished. A retried checkout releases the earlier one.
5. **The shop accepts** within 10 minutes (it gets a ringing alarm). If it doesn't answer, the customer is refunded in full automatically.
6. **A courier accepts** the job (or the customer collects with a 6-digit code). With no courier after 45 minutes, a full automatic refund.
7. **Delivery.** In person, or photo handover. The courier is paid at once.
8. **Returns** within 14 days: the shop approves, and the refund goes back to the same card through Stripe. Hygiene-sealed cosmetics can't be returned once opened (disclosed before purchase); faulty items always can.
9. **Payouts.** The shop's money is released 15 days after delivery (after the withdrawal period), reduced for any return. All transfers carry idempotency keys, so a retry can never pay twice.

**Is it secure today?** The design is. Two things are needed before real money:
- **Stripe is in test mode.** No real card is charged yet. Going live needs the company, Stripe live keys and **`STRIPE_WEBHOOK_SECRET` on Render** (without it, paid orders are never confirmed; the System page lists it as a blocker).
- Payments are cards only for now. MobilePay, Klarna, Google Pay and Apple Pay can be added through Stripe once the account is live.

---

## 3. The customer experience

- **Open the app:** Home is led by search and the All / Women / Men / Kids / Teens switch (Kids → Baby, Toddler, Kids, Junior). Then categories (only those nearby shops stock), the services row (Returns, Track order, Reserve & collect, Size & shade help, Help), the season's collection, "Delivered today" when it's really possible, New in, Second-hand finds and Shops near you.
- **Browse a category:** subcategory chips, filters that fit (size, fit, fabric, colour; or shade, undertone, finish, skin type), sorting, infinite scroll.
- **Product page:**
  - photos and video, shade swatches or sizes with a size guide, price and unit price per litre or kg;
  - materials and care, or ingredients with search, how to use and precautions;
  - the manufacturer and safety block, verified certificates, the hygiene-seal notice;
  - "Report this product".
- **Drops:** a TikTok-style feed of short shop videos with "Buy"; a dot on the tab when there's something new.
- **Checkout:** Delivery or Collect, "When?" (as soon as possible or configured evening slots), door code and instructions, promo code, tip, the exact total, then Stripe. Guests browse freely and sign in only to pay.
- **After paying:** a short celebration, a live map with the courier gliding home, chat with the courier, push updates in Finnish or English, then a rating card and a receipt.
- **Comfort details:**
  - forgot password in 3 steps;
  - reorder with one tap;
  - saved addresses;
  - offline banner, and skeleton screens instead of blank pages;
  - haptics, dark mode, large text support;
  - no fake urgency or hidden fees.

## 4. The merchant experience

- **Joining:** download Malvoya Store → register (accept the Seller Terms; the version and time are recorded and a copy is emailed). A setup checklist then covers details, map pin, opening hours, payouts (Stripe onboarding inside the app), first product, tax info (DAC7), the safety pledge, agreement, and the **automatic business-ID check** against the Finnish Trade Register. Malvoya approves.
- **Adding products, three ways:**
  1. **By hand:** pick the category first, and the editor shows exactly the right form. A lipstick asks for shades (paste a list of names and colours), ingredients and content; a dress asks for a size grid, fabric percentages and care. Missing legal information is shown next to the field, with "Fix next".
  2. **Import from Shopify** (public products.json), **WooCommerce** (API keys) or **CSV.** Products arrive as drafts, sorted into categories automatically, with brand, shades and sizes mapped. A report lists what each product still needs.
  3. **Quick edit** for price, stock and visibility from the list.
- **Brands:** every product has a brand field; the customer app has a Brands A–Z index and brand filters. A brand selling directly joins as its own shop; a retailer selling many brands lists each product with its brand. Brand authenticity (high-risk luxury brands) can require proof.
- **Orders:**
  - a full-screen alarm with the countdown, Accept/Decline, and "Courier at the counter since 14.05" with the order number;
  - pickup code entry, returns with reasons and partial refunds;
  - "Can't fulfil, cancel and refund".
- **Money:** monthly statements (and a printable version), payouts screen, DAC7 data handled.
- **Promotion:** Drops videos filmed in the app, opening hours and "pause orders", share links and QR posters.

## 5. The courier experience

- **Joining:** apply in the app, accept the Courier Agreement, set vehicle and phone, the location explanation, Stripe payouts, then Malvoya approves.
- **Working:**
  - go online (a pre-flight check covers location, notifications and battery saver);
  - offers appear full-screen with the pay already calculated and explained: 4,50 € + 1,10 €/route km, minimum 6,50 €, plus ride-to-shop and waiting pay. These are settings that can change with 15 days' notice, and the offered job keeps its rates;
  - accept, navigate in Google Maps or Waze, swipe to confirm pickup and delivery;
  - chat with the customer;
  - "Can't deliver" after 10 minutes of trying, returning to the shop and keeping the job pay.
- **Earnings:** paid right after each delivery, a day and week chart, tips shown separately (100 % to the courier).

---

## 6. The business: who pays, who earns

| Revenue | Default today | Setting |
|---|---|---|
| Commission on items | 10 % per shop | admin, per shop (0–50 %, audited) |
| Delivery fee | 1,90 € up to 1.5 km + 0,50 €/km, max 6,90 € | `DELIVERY_FEE_*` |
| Service fee | off | `SERVICE_FEE_*` |
| Small-order fee | off | `SMALL_ORDER_*` |

| Cost | Default |
|---|---|
| Courier pay | max(4,50 € + 1,10 €/km, 6,50 €) + extras |
| Stripe | about 1,5 % + 0,25 € per card payment (EEA standard cards) + Connect payout fees |
| Fixed | Render, Cloudinary, Firebase, email, accountant, insurance (about 670 €/month in the plan) |

**The honest number:** at today's defaults every delivered order loses 0,29–8,56 €. With the plan's example prices (20 % commission, 4,90 € base delivery fee, 2 € small-order fee, 20 % pickups) an average order earns about 1,49 € after returns, and the business covers fixed costs at about 15 orders a day. Details and a calculator are in the operating plan. **Prices are the owner's decision and haven't been set yet.**

---

## 7. What protects everyone

- **Money:** Stripe-hosted card entry, signed webhooks, idempotent transfers, automatic refunds on every timeout, payouts held during returns.
- **Accounts:** hashed passwords, rotating refresh tokens, codes for password reset, rate limits, sign-out everywhere after a reset.
- **Law:**
  - consumer rights and the hygiene-seal disclosure;
  - DSA reporting and statements of reasons, P2B terms with 15 days' notice;
  - GDPR export and deletion, DAC7, product safety and recalls;
  - no generic green claims, no profiling of minors.
- **Quality:** 817 automated server checks, GitHub CI on every push, the System page in admin listing anything that blocks real orders.

---

## 8. What still has to happen before real customers

1. **Owner:** company (Oy), bank account, Stripe live + `STRIPE_WEBHOOK_SECRET`, prices, insurance, lawyer review of the texts, Firebase set-up, SMTP email.
2. **Stores:** Google Play account + the 14-day test with 12 testers; Apple account + TestFlight.
3. **Supply:** the first 15 shops and 4–6 couriers in one district.
4. **Testing:** 20 real-money test orders with friends; usability tests.
