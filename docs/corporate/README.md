# Malvoya founder ownership and legal paperwork pack

> **Not legal, tax or accounting advice.** This pack prepares the founder's meetings with a Finnish lawyer (asianajaja / lakimies) and an authorised accountant (tilitoimisto). It was written by the engineering side on 3 November 2026 from the repository and from official sources read that day (listed in each file). Laws, fees and processing times change; check every figure on the official page before acting. Nothing here has been filed, signed or paid. The company does not exist yet: no company name, business ID (Y-tunnus) or register entry may be invented, so they appear as `[PLACEHOLDERS]`.

## What is in the pack

| File | What it is for |
|---|---|
| [01-company-formation.md](01-company-formation.md) | Setting up Malvoya Oy alone: founding agreement, share subscription, share capital, board and deputy, managing director, the ytj.fi start-up notification with every field, tax registers, beneficial owners, costs and timing |
| [02-articles-of-association.md](02-articles-of-association.md) | Draft articles (yhtiöjärjestys) in Finnish and English, built for lasting founder control (A/B shares, redemption and consent clauses), every clause explained |
| [03-ip-and-brand.md](03-ip-and-brand.md) | Moving the code, designs, texts and brand into the company (draft assignment FI/EN), trademark filing, domains and every account in the company's name, 2FA and recovery plan, AI-generated material |
| [04-control-and-investors.md](04-control-and-investors.md) | Keeping control while raising money: term-sheet checklist, shareholders' agreement outline, red flags |
| [05-contracts-templates.md](05-contracts-templates.md) | Employment, contractor, NDA, processor agreements (DPAs) with each provider, and improvements to the seller and courier agreements in `legal/` |
| [06-compliance-calendar.md](06-compliance-calendar.md) | Every recurring deadline in one year |
| [07-placeholder-fill-list.md](07-placeholder-fill-list.md) | Every `[PLACEHOLDER]` in the repo, with file:line, what goes there and when it can be filled |
| [08-risk-register.md](08-risk-register.md) | Top legal and business risks, owner actions and the insurance each needs |

## The order of steps

"Who signs" uses these roles: **Founder** (you, as a person), **Board** (the board of Malvoya Oy: you as the only ordinary member, plus the deputy member), **Company** (Malvoya Oy acting through its board). Fees are those published on the dates given; "assumption" means no official price exists and the figure is an estimate to check.

| # | Step | Free / paid | Typical time | Who signs / does it |
|---|---|---|---|---|
| 1 | **Name and trademark search** for "Malvoya" and 2 back-up names in the trade register name search (ytj.fi), the PRH trademark database and TMview (EU and national marks). Check who holds `malvoya.com` (not under your control today, `CLAUDE.md`). | Free | 1 day | Founder |
| 2 | **Choose the deputy board member** (varajäsen) and ask them in writing (see 01 §4). | Free | 1–2 weeks (a conversation) | Founder; the deputy agrees in writing |
| 3 | **Lawyer review of this pack**: articles (02), founding agreement and subscription (01), IP assignment (03). Decide share capital, number of shares, financial year. | Paid (lawyer, assumption 500–1 500 €) | 1–2 weeks | Founder |
| 4 | **Sign the founding agreement** (perustamissopimus) with the articles attached; this is also the share subscription. If there is share capital: pay it into the bank account for the company being founded. The company must be filed for registration **within 3 months of signing**, or the founding lapses (Companies Act 624/2006, ch. 2 §8). | Free (bank may charge) | 1 day | Founder (as subscriber); the agreement names the board (you + deputy) |
| 5 | **Start-up notification** (perustamisilmoitus) at ytj.fi, online only for an Oy since 1 Jan 2026. Same notification: trade register, VAT register, prepayment register, beneficial owners. Signed with strong electronic identification. | **Paid: 400 €** (own documents, "Alternative B", needed for A/B shares) or **300 €** (guided package with standard articles, "Alternative A") — prh.fi, read 3 Nov 2026 | Processing ≈ 1 week at the moment (PRH processing page on 2 Nov 2026 was handling start-up notifications filed 27 Oct 2026) | Board member(s); the e-service shows exactly who must sign |
| 6 | **Business ID and registration**: wait for the trade register entry. Until registration, contracts made for the company bind the people who made them personally (ch. 2 §10–11): do not sign Stripe live, leases or supplier contracts in the company's name before it. | — | (with step 5) | — |
| 7 | **IP and brand assignment** from you to the company (03 §2), accepted by a board decision; transfer GitHub, Render, Firebase, Stripe, Cloudinary, app-store and domain ownership (03 §4). | Free (lawyer review in step 3) | 1–3 days | Founder (assignor) and Company (assignee: the **deputy** board member decides and signs, because the founder is disqualified from a contract with themself, OYL ch. 6 §4) |
| 8 | **Business bank account** in the company's name; then **accountant** engaged (bookkeeping, VAT returns, financial statements). | Paid (assumption: bank 5–15 €/month; accountant 150–300 €/month, `docs/business/paperwork-checklist.md`) | 1–2 weeks | Company (board) |
| 9 | **Insurance**: business liability, cyber, legal expenses; courier cover depends on the courier model (08). | Paid (quotes) | 1–2 weeks | Company |
| 10 | **YEL pension insurance** for you, if you are a board member or managing director owning over 30 % alone and your work income estimate is at least 9 423,09 €/year (2026 figure, from the paperwork checklist, read 16 Oct 2026). Within 6 months of starting. | Paid (about 24 % of the YEL income, new-entrepreneur discount; assumption) | 1 day | Founder (personally) |
| 11 | **D-U-N-S number** (free) → **Apple Developer Program** (99 USD/year) and **Google Play organisation account** (25 USD once); transfer the three apps to the company account. | Mostly paid | D-U-N-S up to 30 days; Apple 1–2 weeks after | Company (founder as account holder for it) |
| 12 | **Domain and email** in the company's name (.fi and/or .com if available; availability not checked), SPF/DKIM/DMARC. | Paid (assumption 10–30 €/year per domain, 5–8 €/user/month email) | 1 day | Company |
| 13 | **Trademark** "Malvoya" word mark, then the logo, at PRH (Finland) or EUIPO (EU). | Paid: PRH 250 € incl. one class + 100 € per extra class (online, prh.fi read 3 Nov 2026); EUIPO 850 € / +50 € / +150 € each from the third class (paperwork checklist) | PRH ≈ 1 month + 2-month opposition period | Company |
| 14 | **Stripe live** in the company's name (Services Agreement, Connect Platform Agreement, KYC). | Per-transaction fees | 1–7 days | Company (founder as representative) |
| 15 | **Processor agreements (DPAs)** accepted and recorded for Render, Stripe, Firebase/Google, Cloudinary, LiveKit, the email provider, OpenRouteService/HeiGIT, Sentry, Twilio (05 §4). DPIA for courier location. | Free (lawyer time) | 1–2 weeks | Company |
| 16 | **Fill the placeholders** (07) and **lawyer review of the legal texts** in `legal/`; publish them in the admin panel → Legal. | Paid (assumption 1 500–3 000 €, paperwork checklist) | 2–4 weeks | Company |
| 17 | **Courier model decision** (employ or genuinely free freelancers) before the first real delivery; employer register only if employing. | Free decision; employer costs if employing | Before launch | Board |
| 18 | **Shareholders' agreement** (osakassopimus): only when a second shareholder (co-founder, employee with shares, investor) arrives (04). | Paid (lawyer) | 2–4 weeks per round | All shareholders + Company |

## Money summary (one-off, before launch)

| Item | Cost | Source / status |
|---|---|---|
| Start-up notification, own articles (Alternative B) | 400 € | prh.fi, read 3 Nov 2026 |
| — or guided package, standard articles (Alternative A) | 300 € | prh.fi, read 3 Nov 2026 |
| Beneficial owners, VAT and prepayment registers | No separate fee shown in PRH's 2026 fee announcement; filed on the same notification | prh.fi 1 Jan 2026 announcement; confirm in the e-service |
| PRH trademark, 4 classes (9, 35, 39, 42) | 250 + 3 × 100 = 550 € | prh.fi, read 3 Nov 2026 |
| — 6 classes (adding 3 and 25) | 750 € | same |
| EUIPO trademark, 4 classes | 850 + 50 + 150 + 150 = 1 200 € | paperwork checklist (EUIPO page not readable from here on 3 Nov 2026) |
| Apple Developer Program | 99 USD/year | paperwork checklist, 16 Oct 2026 |
| Google Play developer | 25 USD once | paperwork checklist, 16 Oct 2026 |
| Lawyer: company documents + legal texts | ≈ 2 000–4 500 € | assumption |
| Share capital | 0 € allowed (only a public company, Oyj, has a minimum, 80 000 €: Companies Act ch. 1 §3) | Finlex, read 3 Nov 2026 |

## The decisions only the founder can make

1. The company name and two back-ups (after the searches in step 1).
2. Who the deputy board member is (01 §4).
3. Share capital: 0 € or a small amount, and the number of A shares (02 explains why to issue many).
4. Standard articles now and change later (300 €, simpler), or the control articles of 02 from day one (400 €). Recommendation in 02 §0.
5. Financial year (calendar year is simplest).
6. The courier model (employ or freelance), before launch.
7. Holding company or direct ownership (01 §3: tax question for the accountant).

## The 10 most important actions, in order

1. Run the name and trademark searches, and find out who owns `malvoya.com`.
2. Ask and agree with a trusted adult in Finland/EEA to act as deputy board member.
3. Book the lawyer to review 01–03 (articles, founding agreement, IP assignment) in one session.
4. Sign the founding agreement and file the start-up notification at ytj.fi within 3 months (VAT, prepayment, beneficial owners on the same notification).
5. After registration, sign the IP and brand assignment and move every account (GitHub, Render, Firebase, Stripe, Cloudinary, stores, domains) to the company, with 2FA and recovery codes in a company safe.
6. Make the GitHub repository private (it is public today, `CLAUDE.md`), or decide consciously what may stay public.
7. Open the bank account and engage the accountant; register YEL within 6 months.
8. Accept and record the DPAs and do the courier-location DPIA.
9. Fill the placeholders (07), get the lawyer review of `legal/`, decide the courier model, then switch Stripe to live.
10. File the "Malvoya" trademark (at least classes 9, 35, 39, 42) before spending on marketing.
