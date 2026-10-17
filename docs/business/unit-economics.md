# Malvoya unit economics

Prepared 17 October 2026 from `backend/src/config/env.ts`, `utils/pricing.ts`, `utils/courierPay.ts` and `prisma/schema.prisma`. Money in euros. Malvoya's revenue is shown without VAT (25.5 %, divided out of commission and fees). Card fees: Stripe standard EEA cards 1.5 % + 0,25 €; Connect: 0.25 % of transfers (Stripe Finland pricing, read 16 Oct 2026). Courier pay assumes the courier starts within 2 km of the shop and does not wait. Assumptions are marked.

## Code defaults

- Commission 10 % per shop (`Store.commissionRate @default(0.10)`, admin 0–50 %).
- Delivery fee 1,90 € to 1.5 km, +0,50 €/km, max 6,90 € (2,99 € flat if distance unknown).
- Courier pay max(4,50 € + 1,10 € × route km, 6,50 €) + 0,50 €/km ride to shop beyond 2 km (cap 7.5 km) + 0,20 €/min waiting after 5 min (max 4,00 €) + 100 % tip; route km = straight line × 1.3.
- Service fee, small-order fee, slot discount and referrals: off. Promo codes: none, platform-funded.
- Shop payout after 15 days; courier payout on delivery.

## Per order at code defaults

| Basket | km | Customer pays | Commission | Delivery fee | Revenue ex VAT | Courier pay | Card + Connect | Order kept | Fully returned | Expected (15 % returns, assumption) |
|---|---|---|---|---|---|---|---|---|---|---|
| 25 € | 1 | 26,90 € | 2,50 € | 1,90 € | 3,51 € | −6,50 € | −0,73 € | −3,72 € | −7,23 € | −4,25 € |
| 25 € | 3 | 27,65 € | 2,50 € | 2,65 € | 4,10 € | −8,79 € | −0,74 € | −5,43 € | −9,53 € | −6,04 € |
| 25 € | 6 | 29,15 € | 2,50 € | 4,15 € | 5,30 € | −13,08 € | −0,78 € | −8,56 € | −13,86 € | −9,35 € |
| 45 € | 1 | 46,90 € | 4,50 € | 1,90 € | 5,10 € | −6,50 € | −1,07 € | −2,47 € | −7,57 € | −3,24 € |
| 45 € | 3 | 47,65 € | 4,50 € | 2,65 € | 5,70 € | −8,79 € | −1,09 € | −4,18 € | −9,88 € | −5,04 € |
| 45 € | 6 | 49,15 € | 4,50 € | 4,15 € | 6,89 € | −13,08 € | −1,12 € | −7,31 € | −14,20 € | −8,34 € |
| 80 € | 1 | 81,90 € | 8,00 € | 1,90 € | 7,89 € | −6,50 € | −1,67 € | −0,29 € | −8,17 € | −1,47 € |
| 80 € | 3 | 82,65 € | 8,00 € | 2,65 € | 8,49 € | −8,79 € | −1,69 € | −2,00 € | −10,48 € | −3,27 € |
| 80 € | 6 | 84,15 € | 8,00 € | 4,15 € | 9,68 € | −13,08 € | −1,72 € | −5,12 € | −14,80 € | −6,58 € |

Every delivered order loses money at the defaults (−0,29 € to −8,56 €), because courier pay (at least 6,50 €) is far above the customer's delivery fee (1,90–4,15 €).

## VAT

- General rate 25.5 % since 1 Sept 2024 (vero.fi). Reduced 13.5 % since 1 Jan 2026, 10 % newspapers and magazines.
- The shop sells the goods and charges its own VAT. Malvoya sells the marketplace service (commission) to the shop and delivery (plus service/small-order fees) to the customer: Malvoya's taxable supplies at 25.5 %.
- Modelled: commission rate includes VAT; Stripe fees VAT-exempt; courier pay with no deductible VAT (couriers under the 20 000 € threshold). **Assumptions to confirm with an accountant**, together with the disclosed-agent model (Malvoya charges the whole order on its own Stripe account).

## Scenarios (all assumptions)

| | Cautious | Base | Strong | Code defaults |
|---|---|---|---|---|
| Orders/day now | 20 | 40 | 80 | 40 |
| Basket | 45 € | 55 € | 65 € | 45 € |
| Commission | 15 % | 20 % | 22 % | 10 % |
| Delivery fee base / per km / cap | 3,90 € / 0,80 € / 7,90 € | 4,90 € / 0,90 € / 8,90 € | 4,90 € / 0,90 € / 8,90 € | 1,90 € / 0,50 € / 6,90 € |
| Distance | 3 km | 2.5 km | 2.2 km | 3 km |
| Service fee | off | off | 2 % | off |
| Small-order fee | 2,00 € on 30 % | 2,00 € on 20 % | 2,00 € on 15 % | off |
| Pickup share | 10 % | 20 % | 30 % | 0 % |
| Card fee | 1.8 % + 0,25 € | 1.8 % + 0,25 € | 1.8 % + 0,25 € | 1.5 % + 0,25 € |
| Fully returned | 22 % | 15 % | 12 % | 15 % |
| Promo per order | 1,50 € | 0,80 € | 0,50 € | 0,00 € |
| CAC × new customers | 30 € × 80 | 20 € × 100 | 15 € × 200 | 20 € × 100 |
| **Contribution per order** | **−3,88 €** | **1,49 €** | **5,72 €** | **−5,34 €** |
| **Monthly fixed costs** | **644 €** | **668 €** | **716 €** | **668 €** |
| **Break-even orders/day (fixed / incl. marketing)** | **never / never** | **14.8 / 58.9** | **4.1 / 21.4** | **never / never** |
| **First month in profit** | not in 36 | month 19 | month 7 | not in 36 |
| **Cash needed until then** | −252 244 € | −30 857 € | −8 485 € | −478 240 € |

## Fixed costs, Base (per month, assumptions where noted)

| Item | € |
|---|---|
| Render web service (Standard, $25) | 22 |
| Render Postgres basic-1gb + 10 GB ($19 + $3) | 20 |
| Render workspace plan (Hobby free) | 0 |
| Cloudinary Plus ($99/month) | 86 |
| Firebase (push free; phone-code SMS) | 10 |
| Business email | 8 |
| Domain (yearly ÷ 12) | 2 |
| Accountant | 200 |
| Insurance (liability ÷ 12) | 50 |
| Lawyer retainer | 150 |
| Apple Developer ($99/year ÷ 12) | 8 |
| Google Play ($25 once; 0 monthly) | 0 |
| Other tools, phone, bank | 40 |
| Stripe Connect 2 € × (30 shops + 6 couriers) | 72 |
| **Total** | **668** |

USD prices converted at about 0,87 €/$ (assumption). Accountant, insurance, lawyer, email, Firebase SMS and misc are assumptions.

## Market sanity checks (read 16 Oct 2026)

- Wolt: commission about 20–30 % of restaurant sales as reported by Finnish media (KKV); rates are per agreement, pickup pays a reduced rate (merchant.wolt.com).
- Zalando Partner Program: 5–25 % by category (third-party guides).
- Couriers: Wolt says 20–21 € per active hour; PAM (Jan 2026) found under 4 €/h after costs incl. waiting; Wolt employed couriers ~14 €/h while delivering (Yle).
- Foodora left Finland after 27 Feb 2026 (Helsinki Times). Uber Eats launched in Helsinki 6 May 2026, 11 cities/areas by late August (STT Info).

The interactive calculator is in the operating plan page.
