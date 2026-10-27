# Malvoya Privacy Policy / Tietosuojaseloste

**Last updated:** [DATE OF PUBLICATION]

> **Before publishing:** fill in every `[BRACKETED]` item once the company is registered, and have this document reviewed by a Finnish data-protection lawyer. It describes how the Malvoya apps and API actually process data as of this version.

## 1. Controller

[COMPANY LEGAL NAME], Business ID (Y-tunnus) [Y-TUNNUS], [STREET ADDRESS], [POSTCODE] [CITY], Finland.
Contact for privacy matters: the contact form at https://malvoya-api-eu.onrender.com/contact (topic "Privacy (GDPR) request")

Malvoya is a marketplace. Stores that sell through Malvoya are independent sellers. For the order data they need to fulfil your purchase, each store is a separate controller.

## 2. What we process, why, and on what legal basis

| Data | Purpose | Legal basis (GDPR Art. 6) |
|---|---|---|
| Name, email and/or phone number, password (stored only as a one-way hash) | Create and secure your account; sign-in codes | Contract (6(1)(b)) |
| Delivery address, delivery location and order notes | Deliver your order | Contract (6(1)(b)) |
| Orders, prices, refunds and returns | Sale, returns and bookkeeping | Contract; legal obligation under the Accounting Act (6(1)(c)) |
| Payment status and Stripe payment reference | Confirm payment and issue refunds. **We never receive or store card or bank account numbers**; Stripe processes them. | Contract; legal obligation |
| Courier location, only while the courier is online | Show the courier's position to the customer and store of an active order; offer jobs to nearby couriers; calculate pay for the ride to the store when a job is accepted (only the distance is stored) | Contract with the courier (6(1)(b)) |
| Store business details (for sellers) | Verify sellers; tax reporting on marketplace sellers (DAC7) | Contract; legal obligation |
| Seller tax details (DAC7): for business sellers the legal name, business ID (Y-tunnus), VAT number if any and registered address; for private sellers the legal name, date of birth, tax identification number (for Finnish residents the personal identity code, henkilötunnus) and home address; and each seller's yearly number of sales, amounts paid to them and commissions per quarter | Report sellers to the Finnish Tax Administration once a year, as the EU directive on reporting by digital platforms (DAC7, Council Directive (EU) 2021/514) requires. We collect only what that report needs | Legal obligation (6(1)(c)) |
| Monthly sales statements (for sellers) | Give each seller a statement of their sales, refunds, commission and payouts | Contract (6(1)(b)); legal obligation (Accounting Act) |
| Chosen delivery time (if you book a delivery slot) | Have the store prepare the order and offer it to couriers in time for that slot | Contract (6(1)(b)) |
| Drops you like, views of drops (counted once per day; for signed-out viewers we keep only a one-way scrambled form of the IP address, which changes every day — nothing is stored on your phone for this), favourites and reviews | Show likes and favourites, rank the Drops feed, show verified reviews | Contract (6(1)(b)); legitimate interest (6(1)(f)) |
| Delivery photo and the courier's position at handover, when the order is left at the door | Proof of delivery | Contract; legitimate interest |
| Push notification token of your phone | Send order, delivery and payout updates. No marketing. | Contract (6(1)(b)) |
| Photos and videos stores upload (products, drops) | Show them in the app | Contract with the store |
| Payout details (for stores and couriers) — collected by Stripe, not by Malvoya | Pay stores and couriers | Contract; legal obligation (anti-money-laundering) |
| Order chat messages between the customer and the courier | Let you and your courier agree on the handover, also after a lost connection | Contract (6(1)(b)) |
| Your language choice (Finnish or English), from your app's language setting | Send notifications and emails in your language | Contract (6(1)(b)) |
| Acceptance records: which document (terms, seller terms, courier agreement, privacy policy) and exact version you accepted, when, how (when signing up or in the app), your network address shortened to its first part (IPv4: the first three of four numbers; IPv6: the first three of eight groups), your phone's or browser's user-agent text (at most 200 characters) and the app version | Prove which agreement applies to you and that you accepted it; send you a copy of what you accepted | Contract (6(1)(b)); legitimate interest in being able to prove the contract (6(1)(f)) |
| For business sellers: the result of looking up the business ID (Y-tunnus) in the Finnish Patent and Registration Office's open company register (YTJ) — whether it was found, the registered name, the registration date and whether the company is still active | Check the trader information sellers give us, as the Digital Services Act (Art. 30) asks marketplaces to do with free official databases. The result only helps our team; a person always decides on approval. We send PRH only the business ID | Legal obligation (6(1)(c)); legitimate interest (6(1)(f)) |
| For couriers: vehicle type, and when you confirmed you read how your location is used | Onboarding and offering suitable jobs | Contract (6(1)(b)) |
| Reports you make about a product ("Report this product"): the product, the reason, what you wrote, and your account or, if you are not signed in and choose to give it, your email address | Process the notice (Digital Services Act Art. 16; product safety notices under the General Product Safety Regulation) and tell you the outcome | Legal obligation (6(1)(c)) |
| Your purchases of a product that is recalled for safety reasons | Tell you directly about the recall by push notification and email, also if you switched marketing off; we keep a record of when we told you | Legal obligation (6(1)(c), GPSR Art. 22(12) and 35) |
| Whether you are known or likely to be under 18 | Never show you recommendations based on profiling (Digital Services Act Art. 28) | Legal obligation (6(1)(c)) |
| Users you blocked, and reports you make about comments or reviews | Hide blocked users' content for you; let our team review reported content | Legitimate interest (6(1)(f)); legal obligation (Digital Services Act) |
| Technical logs (IP address, error logs) | Security and abuse prevention | Legitimate interest (6(1)(f)) |

We do not sell personal data, and we do not use your data for advertising profiling.

## 3. Location data

- **Customers:** we use the delivery address and coordinates you enter. The app does not track you in the background.
- **Couriers:** while you are online, your position is shared with the customer and store of the order you are delivering. We keep only your latest position, and it is deleted as soon as you go offline. We do not store a history of your routes.

## 4. Automated decisions and recommendations

**Drops feed.** "For you" ranks drops by how new they are, how people respond to them (likes, shares, views watched to the end), the distance of the store from your delivery address when you share it, and the store's rating. We do not build a personal profile for it. "Latest" shows drops newest first, with no ranking. You can switch at any time (Digital Services Act Art. 27).


Delivery jobs are offered to approved, online couriers within 7.5 km of the store, nearest first. Couriers choose which jobs to accept. No job is assigned automatically, and no decision with legal or similarly significant effects is made solely by automated means (GDPR Art. 22). Couriers can ask a person, through Support in the courier app or the contact form at https://malvoya-api-eu.onrender.com/contact, to explain or review any decision.

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
- **The Finnish Patent and Registration Office (PRH)**, for business sellers only: we look up the business ID in its free open data service (avoindata.prh.fi). PRH receives only the business ID, not who asked.
- **Authorities**, where the law requires it (for example the Finnish Tax Administration for DAC7 seller reporting).

**Seller tax details (DAC7).** A seller's tax identification number is stored encrypted (AES-256) and is shown to the seller only in part (its last characters). It is decrypted only for Malvoya's yearly report, which only Malvoya's administrators can open, and it is sent only to the Finnish Tax Administration; that authority may share it with the tax authorities of other EU countries where the seller lives, as the directive provides. Sellers who stay under the directive's threshold (fewer than 30 sales and at most 2 000 € in a year) are not reported, but their details are kept as the law requires.

## 6. Transfers outside the EU/EEA

Our servers and database are hosted by Render in Frankfurt, Germany (EU). Some providers (Google, Twilio, Stripe, Cloudinary) may process data in the United States under the EU–US Data Privacy Framework or Standard Contractual Clauses.

## 7. How long we keep data

| Data | Retention |
|---|---|
| Account data | Until you delete your account |
| Orders, receipts, refunds | 6 years from the end of the financial year (Accounting Act 2:10); anonymised if you delete your account earlier |
| Seller tax details and the yearly DAC7 report data | 10 years from the end of the year the data was reported for (DAC7), also if the seller deletes their account |
| Courier live location | Until the courier goes offline |
| Delivery photos and handover position | 30 days after delivery |
| Drop views | Counted per day; the daily record keeps no content beyond the viewer key |
| Push tokens | Until you sign out or uninstall the app |
| Sign-in codes | 10 minutes |
| Password reset codes | 15 minutes |
| Order chat messages | 30 days after the order is completed or cancelled (deleted with your account) |
| Blocks and reports you made | Until you remove the block or delete your account |
| Product reports you made | The report is kept as a record of the notice and its decision; your account and email address are removed from it when you delete your account |
| Recall notices sent to you | As long as the recall record is kept (product safety records), and anonymised with your account |
| Acceptance records (agreement versions you accepted) | For as long as you have an account and 10 years after it is deleted, then deleted automatically. Why: they are our proof of which contract applied and that you agreed to it, and claims based on a contract or its breach can in some cases still be made up to 10 years later under Finnish law (Act on the Limitation of Debts 728/2003). The record holds only what that proof needs: the network address is shortened so it does not identify a single connection |
| Business ID check results (sellers) | Kept with the store; replaced when the check is run again; deleted with the store |
| Refresh tokens (sessions) | 7 days |
| Security logs | [30] days |

## 8. Your rights

You can:
- **access** your data and **export** it (Profile → Privacy → Download my data);
- **correct** your data;
- **delete** your account (Profile → Privacy → Delete account; how in each app: [malvoya-api-eu.onrender.com/legal/delete-account](https://malvoya-api-eu.onrender.com/legal/delete-account)). Order records we must keep by law are anonymised rather than deleted. Your sign-in record at Google Firebase and, for a store, its photos and videos at Cloudinary are deleted too;
- **object** to processing based on legitimate interest;
- **restrict** processing.

Use the contact form at https://malvoya-api-eu.onrender.com/contact (topic "Privacy (GDPR) request") or Support in the app. We reply within one month.

You also have the right to lodge a complaint with the **Data Protection Ombudsman (Tietosuojavaltuutetun toimisto)**, tietosuoja.fi, PL 800, 00531 Helsinki.

## 9. Security

- Passwords are hashed with bcrypt.
- Sessions use short-lived tokens, and refresh tokens are stored only as hashes.
- All traffic is encrypted (HTTPS).
- Access to live order data is limited to the customer, store and courier of that order.

## 10. Children

Malvoya is intended for people aged 18 or over. Couriers and sellers must be adults.

## 11. Changes

Every change to this policy is published as a new version with a summary of what changed and the date it takes effect. We tell you by push notification and email, in your language, before the change takes effect (or at the latest when it does, if the law requires a change at once). Every version, with its dates, stays readable at [malvoya-api-eu.onrender.com/legal/privacy/versions](https://malvoya-api-eu.onrender.com/legal/privacy/versions). The app asks you to confirm you have read the new version; this is an acknowledgement, not consent, and it never blocks you from using your account, exporting your data or deleting it.
