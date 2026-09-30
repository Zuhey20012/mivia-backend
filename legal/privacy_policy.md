# Malvoya Privacy Policy / Tietosuojaseloste

**Last updated:** [DATE OF PUBLICATION]

> **Before publishing:** fill in every `[BRACKETED]` item once the company is registered, and have this document reviewed by a Finnish data-protection lawyer. It describes how the Malvoya apps and API actually process data as of this version.

## 1. Controller

[COMPANY LEGAL NAME], Business ID (Y-tunnus) [Y-TUNNUS], [STREET ADDRESS], [POSTCODE] [CITY], Finland.
Contact for privacy matters: [privacy@malvoya.com]

Malvoya is a marketplace. Stores that sell through Malvoya are independent sellers. For the order data they need to fulfil your purchase, each store is a separate controller.

## 2. What we process, why, and on what legal basis

| Data | Purpose | Legal basis (GDPR Art. 6) |
|---|---|---|
| Name, email and/or phone number, password (stored only as a one-way hash) | Create and secure your account; sign-in codes | Contract (6(1)(b)) |
| Delivery address, delivery location and order notes | Deliver your order | Contract (6(1)(b)) |
| Orders, prices, refunds and returns | Sale, returns and bookkeeping | Contract; legal obligation under the Accounting Act (6(1)(c)) |
| Payment status and Stripe payment reference | Confirm payment and issue refunds. **We never receive or store card or bank account numbers**; Stripe processes them. | Contract; legal obligation |
| Courier location, only while the courier is online | Show the courier's position to the customer and store of an active order; offer jobs to nearby couriers | Contract with the courier (6(1)(b)) |
| Store business details (for sellers) | Verify sellers; tax reporting on marketplace sellers (DAC7) | Contract; legal obligation |
| Drops you like, views of drops (counted once per day; for signed-out viewers we keep only a one-way scrambled form of the IP address, which changes every day — nothing is stored on your phone for this), favourites and reviews | Show likes and favourites, rank the Drops feed, show verified reviews | Contract (6(1)(b)); legitimate interest (6(1)(f)) |
| Delivery photo and the courier's position at handover, when the order is left at the door | Proof of delivery | Contract; legitimate interest |
| Push notification token of your phone | Send order, delivery and payout updates. No marketing. | Contract (6(1)(b)) |
| Photos and videos stores upload (products, drops) | Show them in the app | Contract with the store |
| Payout details (for stores and couriers) — collected by Stripe, not by Malvoya | Pay stores and couriers | Contract; legal obligation (anti-money-laundering) |
| Technical logs (IP address, error logs) | Security and abuse prevention | Legitimate interest (6(1)(f)) |

We do not sell personal data, and we do not use your data for advertising profiling.

## 3. Location data

- **Customers:** we use the delivery address and coordinates you enter. The app does not track you in the background.
- **Couriers:** while you are online, your position is shared with the customer and store of the order you are delivering. We keep only your latest position, and it is deleted as soon as you go offline. We do not store a history of your routes.

## 4. Automated decisions and recommendations

**Drops feed.** "For you" ranks drops by how new they are, how people respond to them (likes, shares, views watched to the end), the distance of the store from your delivery address when you share it, and the store's rating. We do not build a personal profile for it. "Latest" shows drops newest first, with no ranking. You can switch at any time (Digital Services Act Art. 27).


Delivery jobs are offered to approved, online couriers within 7.5 km of the store, nearest first. Couriers choose which jobs to accept. No job is assigned automatically, and no decision with legal or similarly significant effects is made solely by automated means (GDPR Art. 22). Couriers can ask a person at [support@malvoya.com] to explain or review any decision.

## 5. Who receives your data

- **The store** you buy from: your name, the items ordered and the delivery address.
- **Your courier:** the delivery address, but only after they accept the job. Before that, couriers see only the approximate area.
- **Service providers (processors)** under data-processing agreements:
  - Stripe Payments Europe (payments; payouts to stores and couriers through Stripe Connect)
  - Cloudinary (storing and delivering photos and videos)
  - Google Firebase (sign-in, push notifications)
  - Render (hosting and database)
  - Twilio (SMS codes)
  - [EMAIL PROVIDER] (email)
- **Authorities**, where the law requires it (for example the Finnish Tax Administration for DAC7 seller reporting).

## 6. Transfers outside the EU/EEA

Hosting is provided by Render. [STATE REGION: "in Frankfurt, Germany (EU)" once migrated. Until then: "in the United States under the EU Standard Contractual Clauses / EU–US Data Privacy Framework".] Some providers (Google, Twilio, Stripe) may process data in the United States under the EU–US Data Privacy Framework or Standard Contractual Clauses.

## 7. How long we keep data

| Data | Retention |
|---|---|
| Account data | Until you delete your account |
| Orders, receipts, refunds | 6 years from the end of the financial year (Accounting Act 2:10); anonymised if you delete your account earlier |
| Courier live location | Until the courier goes offline |
| Delivery photos and handover position | 30 days after delivery |
| Drop views | Counted per day; the daily record keeps no content beyond the viewer key |
| Push tokens | Until you sign out or uninstall the app |
| Sign-in codes | 10 minutes |
| Refresh tokens (sessions) | 7 days |
| Security logs | [30] days |

## 8. Your rights

You can:
- **access** your data and **export** it (Profile → Privacy → Download my data);
- **correct** your data;
- **delete** your account (Profile → Privacy → Delete account). Order records we must keep by law are anonymised rather than deleted;
- **object** to processing based on legitimate interest;
- **restrict** processing.

Contact [privacy@malvoya.com]. We reply within one month.

You also have the right to lodge a complaint with the **Data Protection Ombudsman (Tietosuojavaltuutetun toimisto)**, tietosuoja.fi, PL 800, 00531 Helsinki.

## 9. Security

- Passwords are hashed with bcrypt.
- Sessions use short-lived tokens, and refresh tokens are stored only as hashes.
- All traffic is encrypted (HTTPS).
- Access to live order data is limited to the customer, store and courier of that order.

## 10. Children

Malvoya is intended for people aged 18 or over. Couriers and sellers must be adults.

## 11. Changes

We will notify you in the app before material changes take effect.
