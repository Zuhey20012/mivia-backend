# Malvoya operating plan

Prepared 17 October 2026 from the code in this repository and public sources (read 16 October 2026). Malvoya is pre-launch: no company, shops, couriers, customers or partners exist yet, and nothing here claims otherwise. Assumptions are marked **(assumption)**. Companion files: `unit-economics.md`, `paperwork-checklist.md`, `api-route-map.md`. The interactive version (calculator, charts) is the "Malvoya Operating Plan" page.

## 1. Executive summary

Malvoya is a hyperlocal fashion marketplace for Finland. Customers buy clothes from local shops, watch shoppable videos ("Drops"), and get the order by courier now, in a "Tonight" slot (17–19, 19–21), or reserve it and collect it in the shop. The API also has rentals. There are three Flutter apps (customer, store, courier), a React admin panel and a Node API on Render in Frankfurt.

**Who pays whom**

1. The customer pays Malvoya once: items + delivery fee + optional service/small-order fee + tip − promo. The charge is on Malvoya's own Stripe account; shops and couriers are Stripe Connect Express accounts paid by separate transfers.
2. The shop gets items − commission, 15 days after delivery (held while a return is open).
3. The courier gets the formula pay right after delivery, plus 100 % of tips.
4. Malvoya keeps commission + delivery fee + fees − courier pay − Stripe fees − promos − refunds it carries.

**Code defaults:** commission 10 % per shop (admin 0–50 %); delivery fee 1,90 € to 1.5 km, +0,50 €/km, max 6,90 €; courier pay max(4,50 € + 1,10 €/route km, 6,50 €) + ride to shop beyond 2 km at 0,50 €/km + waiting after 5 min at 0,20 €/min (max 4 €); service fee, small-order fee, slot discount and referrals **off**; no promo codes.

**Headline:** at the defaults every delivered order loses money: −0,29 € to −8,56 € across 25/45/80 € baskets at 1/3/6 km, before returns. Courier pay (≥ 6,50 €) is far above the delivery fee (1,90–4,15 €). The fix is pricing, which is already configurable: in the **Base** scenario (assumption: 20 % commission, 4,90 € base delivery fee, 2 € small-order fee on 20 % of orders, 20 % pickup, 15 % full returns) an order earns about **1,49 €** after returns, fixed costs are about **668 €/month**, break-even is **14.8 orders/day** on fixed costs alone and **58.9 orders/day** with 2 000 €/month marketing. On the Base growth curve (5 orders/day, +15 %/month) the first month in profit is month 19, with about 30 900 € cumulative loss before it (before founder pay and one-off costs).

## 2. Revenue levers (effect per 55 € / 2.5 km order, assumptions)

| Lever | Status | Effect | Risk |
|---|---|---|---|
| Commission 18–20 % (founding shops 12 % for 90 days) | Setting, per shop, audited | 10 → 20 %: +4,38 € | Shops refuse; 15 days' notice (P2B) |
| Delivery fee 4,90 € base, +0,90 €/km, cap 8,90 € | Setting `DELIVERY_FEE_*` | +2,71 € per delivered order | Checkout drop-off vs Wolt+/Uber One |
| Service fee 2 % (0,50–2,50 €) | Setting `SERVICE_FEE_*` | +0,88 € | Must be in the total price shown before purchase |
| Small-order fee 2 € under 30 € | Setting `SMALL_ORDER_*` | +1,59 € on those orders | Fewer small baskets |
| Reserve & collect | Built | ~7,30 € per pickup order at 20 % | Less convenient |
| Tonight batching | Slots built; pay is per job, needs a second-drop pay rule (code) | ~+0,60 € avg if 30 % batch | Seen as a pay cut; explain before acceptance (PWD) |
| Sponsored Drops/search, labelled "Sponsored / Mainos" | Not built; shop terms say no paid placement | 50–200 €/shop/month once traffic exists | Ad labelling (UCPD/Omnibus), P2B Art. 5 ranking terms, 15 days' notice; DSA Art. 26/27 as good practice |
| Promo codes, referrals | Built, off | A cost | Discount-only customers |
| Courier pay min 6,50 → 5,90 € | Setting | ≤ 0,60 € on short trips only | Courier supply |
| Malvoya+ subscription | Future idea only | Not modelled | Replaces delivery income; needs 2+ orders/month |

Order of moves: set prices before the first real order → launch with pickup as the hero → hourly couriers in fixed hours → batching pay at 15+ orders/day → sponsored Drops at ~1 000 weekly feed users.

## 3. MVP and routes to launch (targets are assumptions)

**Phase 0 — paperwork and integrations (weeks 0–6).** Paperwork steps 1–12. Render env: Stripe live keys + webhook secret, `SMTP_*`, `SUPPORT_EMAIL`, `FIREBASE_SERVICE_ACCOUNT`, `CLOUDINARY_*`, `DATA_ENCRYPTION_KEY`, `ANDROID_APP_SHA256`, fee settings. Upgrade Render Starter → Standard. Fill every `[PLACEHOLDER]` in `legal/`, lawyer review. 20 real-money test orders (incl. a return, a failed delivery, a pickup). *Exit:* Oy registered, Stripe live verified, admin System clean, legal pages live, apps on the final Play account, test orders reconciled.

**Phase 1 — closed beta in one Helsinki district (8–12 weeks).** One walkable area ~3 km across (e.g. Punavuori–Kamppi or Kallio; choose with admin → Launch demand). 20–30 shops signed, 15+ live (30+ items, opening hours, 3–5 Drops each). 4–6 couriers (2 on shift) + founder. "Malvoya hours" (e.g. Thu–Sun 12–20). Waiting list invited in waves of 100. *Exit:* 15+ orders/day for 4 weeks, on time ≥ 90 %, cancellations ≤ 5 %, median shop acceptance ≤ 4 min, 30-day repeat ≥ 25 %, contribution ≥ 2 €/order.

**Phase 2 — Helsinki, Espoo, Vantaa (months 4–12).** One district at a time with 15+ live shops before opening; 80–120 shops, 15–25 couriers, daily hours; first hire shop success/sales; Redis for rate limits and Socket.io before a second instance; iPhone app. *Exit:* 60+ orders/day, first district profitable after marketing, CAC paid back in 3 months.

**Phase 3 — other cities (year 2).** Tampere, Turku, Oulu; 30 shops pre-signed and a part-time city lead per city; Phase 1 exit criteria per city.

**Recruiting scripts**
- Shops: "Hei! I'm building Malvoya, an app for local fashion shops in [district]. People see your clothes in short videos and get them delivered today, or reserve them and pick them up from you. You pay nothing to join and [12] % only when you sell, for the first 90 days. I'll film your first five videos myself today."
- Couriers: "Short trips, no hot food. You see the pay before you accept: 4,50 € plus 1,10 € per km, at least 6,50 €, extra for long rides to the shop and waiting, all tips yours. For the beta we also pay [x] € an hour for set shifts. Paid after every delivery."
- Customers: "Malvoya is open in [district]! [n] local shops, delivered today or ready for pickup. First order: [code] gives [5] € off (orders over [30] €, until [date])."

**KPIs:** orders/day, AOV, on-time %, cancellation % by reason, 30-day repeat, store acceptance time and rate, return rate, net platform revenue — all in admin → Analytics. Courier utilisation is **not tracked in code** (use a shift sheet). CAC = your spend ÷ new customers. Contribution = net platform revenue − courier pay − card fees − promos.

**Weekly rhythm:** daily 10-min check of System, Support and Moderation; Mon KPIs and one decision; Tue shop calls; Wed filming Drops; Thu courier shifts; Fri money (Stripe balance, refunds, disputes, receipts to the accountant); monthly statements, VAT return, DAC7 completeness, pricing review with 15 days' notice.

## 4. Daily operations

**Automatic (order watchdog, every minute, `services/orderWatchdog.ts`):** unpaid checkout cancelled at 30 min; shop reminder at 3 min, full refund at 10 min; re-offer to couriers every 2 min (7.5 km, nearest first, else all online); delay notice at 15 min; full refund at 45 min (scheduled orders from slot start); scheduled first offer at slot − prep − 15 min; pickup reminder 24 h, refund 72 h; pickup never ready refunded at 24 h. Payouts every 10 min; delivery photos purged after 30 days.

- **Shop onboarding:** visit and demo → seller terms → store created, admin approves after checking Y-tunnus and trader details → Stripe Express onboarding → DAC7 tax details → import (Shopify/WooCommerce/CSV) and publish → opening hours → 3–5 Drops → test order → QR poster.
- **Courier onboarding:** call → ID, right to work, insurance, Y-tunnus or employment contract → admin approval → Stripe Express → ride-along (arrived-at-shop, photo handover, delivery problem) → explain the pay rule; any job can be refused.
- **Dispatch / no courier:** first to accept wins, nothing auto-assigned; at 5 min the founder phones couriers; at 10 min the founder delivers or the customer reorders as pickup; the 45-min refund is the last line.
- **Support:** admin → Support (+ email if `SUPPORT_EMAIL`); promise 15 min for live orders in Malvoya hours, 24 h otherwise **(proposal)**; saved replies; order chat kept 30 days.
- **Refunds and returns:** 14 days from delivery, per item; shop approves; `REFUNDED` sends a real Stripe refund; final return refunds the delivery fee too; shop payout held then reduced by goods less commission. **Open decision:** who pays the return trip.
- **Failed delivery:** courier reports, waits 10 min, returns to shop; order cancelled, items refunded, delivery fee and tip kept, courier paid, no shop payout or commission.
- **Fraud:** Stripe SCA and fraud screening; 20 € per dispute; verified-sign-in protections and rate limits; first-order-only promos; manual look at first orders over 200 € **(rule of thumb)**; blocks.
- **Moderation:** Drops auto-hide after 3 reporters, comments and reviews after 3 reports; admin removal needs a reason and emails a statement of reasons.
- **Payouts:** courier on delivery, shop after 15 days; keep about 2 weeks of courier pay as a Stripe buffer; failed transfers → admin retry.

**One-person company:** founder does shop sales, courier ops (and delivers in weeks 1–4), support and moderation, weekly money check. Buy from day one: accountant, lawyer review. First hire: part-time shop success (Phase 2); then a courier shift lead; part-time support above ~40 orders/day.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Chicken and egg (shops vs customers) | One district, 15+ live shops before customers, waiting list, shop share links and QR posters |
| Courier supply (Wolt, Uber Eats since 6 May 2026) | Hourly shifts, founder delivers, pickup, Tonight slots |
| Unit economics at low volume | Set prices before launch, push pickup, cap promos, grow only while contribution holds |
| Fashion returns | Video and size info, try-in-shop pickup, return-fee decision, per-shop return rate |
| Platform work rules (draft law in force 2.12.2026 planned; KHO May 2025 Wolt ruling) | Employed hourly couriers first, or genuinely free freelancers; lawyer review |
| VAT / agent model (Malvoya takes the full payment) | Disclosed-agent terms, shop receipts, accountant sign-off |
| Cash and Stripe balance | Stripe buffer, keep 15-day shop hold, read Stripe reserve terms |
| Single person | Fixed hours, auto-refund timers, second admin account |
| Brand and domain (`malvoya.com` not controlled, no trademark) | Trademark search and filing, own domain |
| Big platforms add local fashion | Compete on curation, video and shop relationships |

**Assessment:** the software is ready before the business is. With defaults Malvoya loses money on every order; with sensible prices it earns a few euros per order, but only with dense supply in one area, many pickups and controlled returns. Prove it cheaply in Phase 1 before raising money or buying ads.
