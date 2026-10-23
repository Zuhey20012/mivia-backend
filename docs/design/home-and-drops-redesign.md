# Design: consumer-centred Home, Drops as their own destination, and role-first homes for the store and courier apps

**Status:** Proposed, 22 Oct 2026. Builds on the category taxonomy (`docs/compliance/product-data-spec.md`), the shared design system (`packages/malvoya_ui`) and ADR-001.

## 1. Requirements

### Functional
- **Customer Home** answers "what can I buy near me, today?" in one glance, led by categories and subcategories, with an audience switch (All / Women / Men / Kids).
- **Drops** (shoppable videos) live only in their own tab. Home no longer has the big "Drops near you" tile. The tab tells you when there is something new.
- **Store app Home** answers "what needs me right now?" (orders waiting, today's sales, setup left).
- **Courier app Home** answers "am I online, and is there a job?" (online switch, active job, offers).
- Every section shows only real data. Empty sections hide instead of showing filler.

### Non-functional
| Goal | Target |
|---|---|
| Time to first useful content (Home, 4G) | < 1.5 s with cache, < 3 s cold |
| Scroll smoothness | 60 fps on a mid-range Android (Galaxy A-series); no frame > 32 ms in the Home list |
| Availability of Home | 99.9 %; Home renders from the last cached response when offline |
| Accessibility | WCAG 2.1 AA: 4.5:1 text contrast, 48 dp targets, text scale 1.3 without overflow, reduce-motion respected |
| Privacy | No profiling without consent; a non-personalised Home is always available (DSA Art. 27/38 spirit) |
| Cost | Home served mostly from cache: < 1 DB query per 10 Home opens at scale |

### Constraints
One developer today, the existing Node/Prisma/Postgres API on Render, Flutter apps, and the Cloudinary CDN for media.

## 2. Why move Drops out of Home (the decision)

**Today:** Home opens with a large purple "Drops near you" tile plus "Second Hand" and "Eco-Friendly" tiles. Categories come only below them, and stores below that. Drops also have their own tab, so the tile duplicates the tab.

**The proposal is right**, for four reasons:
1. **Intent.** People open Home to *find* something; they open video to *browse*. Mixing a full-bleed video promo into a search surface slows down the shoppers who came with a goal. TikTok Shop and Instagram keep video as its own surface; Zalando and Sephora lead Home with categories.
2. **Space.** The tile takes about 40 % of the first screen. Giving that space to categories puts every product type within one thumb movement.
3. **Performance.** A video promo on Home tempts autoplay and preloading on the most important screen. A separate tab loads video only when asked, which is faster and saves mobile data.
4. **Honesty and focus.** With few shops at launch, a big Drops tile is often empty or repetitive. A categories-first Home stays useful even with 15 shops.

**What we keep:** Drops stay as tab 3, in the centre of the bar, with:
- a sunshine dot on the tab when shops you follow (or shops near you) posted since your last visit;
- Drops still opening straight from a store page and from product pages ("Watch it on video");
- deep links (`/d/:id`) opening the Drops tab at that video.

**Trade-off:** Drops discovery drops a little for people who never tap the tab. It is mitigated by the dot, by store and product entry points, and by the first-run intro screen that already introduces Drops. We measure the effect (§7) and revisit.

## 3. Customer Home: information architecture (top to bottom)

```
┌───────────────────────────────────────┐
│ Deliver to: Kallio ▾        (bell)    │  address picker; bell for order updates
│ [ Search lipstick, dresses, shops  ]  │  search first: the highest-intent action
│ ( All | Women | Men | Kids )          │  audience switch filters everything below
├───────────────────────────────────────┤
│ Active order card (only when one runs)│  live status, ETA or pickup code
├───────────────────────────────────────┤
│ Shop by category  ▸ 3×3 pastel tiles  │  Clothing … Fragrance, Second-hand
│   tap → subcategory chips + filters   │  only categories with stock nearby
├───────────────────────────────────────┤
│ Delivered today / <slot>   ▸ rail     │  title from configured slots; hidden if none
│ New in near you            ▸ rail     │  freshest available items
│ Second-hand finds          ▸ rail     │  from private + vintage sellers
│ Shops near you             ▸ list     │  open now first, then by distance
└───────────────────────────────────────┘
   Home · Search · Drops(●) · Orders · Profile
```

**Rules for every rail:**
- 2.5 cards visible, so it is clear the rail scrolls.
- "See all" opens the filtered catalogue.
- At most 2 items per shop in a rail, for diversity.
- Hidden when it has fewer than 4 items.

Product card, the same everywhere:
- image 4:5;
- price, with the unit price for beauty;
- shop name and distance;
- one status chip at most ("Tonight", "Second-hand", "Certified");
- the heart in the corner.

**Real-world references:**
- Wolt Home: search plus category strip plus venue rails, with venues "open now" first.
- Zalando: an audience switch at the top, category tiles, then campaigns.
- Sephora and Lyko: product-type categories and a "new" rail.
- Vinted: second-hand finds as a rail with condition chips.

## 4. Store and courier homes (role-first)

**Store app Home** (the Wolt Merchant pattern):
1. a status bar ("Open · accepting orders" toggle, opening hours, a notifications warning if they are off);
2. orders waiting, as big cards with a countdown (the full-screen alert already exists);
3. today's summary (orders, sales, waiting);
4. the setup checklist until it is done;
5. returns needing action;
6. a low-stock list.
Products, Drops and statements are tabs, not Home.

**Courier app Home** (the Uber Driver pattern):
1. a big Online/Offline switch with the go-online checklist;
2. the active job card, which takes over the screen during a delivery;
3. incoming offers;
4. today's earnings strip.
Everything else (earnings history, account, help) is one tap away. The map is shown only when it helps: on an active job, or when an offer is being considered.

## 5. The engine (server design)

### 5.1 Server-driven Home sections
Instead of hard-coding the Home order in the app, the API returns typed sections. The app renders them with `malvoya_ui` components.

```
GET /api/v1/home?lat&lng&audience=all|women|men|kids&locale=fi
→ { ok, generatedAt, ttlSeconds, sections: [
     { type:"active_order",  order:{...} }?,                        // per user, never cached
     { type:"categories",    items:[{slug,name,icon,tile,count}] },
     { type:"product_rail",  key:"tonight", title:{en,fi}, seeAll:{query}, items:[productCard...] },
     { type:"product_rail",  key:"new_in", ... },
     { type:"product_rail",  key:"second_hand", ... },
     { type:"store_list",    key:"near_you", items:[storeCard...] }
  ], dropsBadge: { newSince: ISO|null } }
```

- **Why server-driven:** the order, rails and seasonal sections change without an app release. A/B tests run on the server. Old apps ignore unknown section types (forward compatible).
- **Caching:**
  - The anonymous part (categories, rails, stores) is keyed by `geohash(5) + audience + locale`, a ~5 km cell.
  - It is cached in Redis (or in memory with one instance) for 60 s and served with `Cache-Control: public, max-age=30, stale-while-revalidate=120` for a CDN.
  - The personal part (active order, the Drops badge) is fetched separately and is small.
- **Ranking for rails (v1, rule-based, explainable):**
  - Filters: available, in delivery reach, store open now or opening within 2 h, store acceptance rate above a floor.
  - Score: freshness (new in) or the slot fit (tonight).
  - Diversity: at most 2 items per store.
  - The ranking explanation is published next to the existing `RANKING_EXPLANATION` (P2B Art. 5 for shops; DSA recommender transparency for consumers).
  - Personalised ranking (follows, favourites, sizes) comes later and only with consent. A non-personalised option is always available.

### 5.2 Drops engine (unchanged API, better client)
- It keeps `GET /drops/feed` and the existing ranking.
- New: `GET /drops/badge` → `{ newSince }` (or a field in `/home`) drives the tab dot. A cheap indexed query ("max createdAt of drops from followed or nearby stores > lastSeen").
- Client: the player starts only when the tab is visible. It preloads ±1 video and uses HLS from Cloudinary (adaptive bitrate) with poster frames.

### 5.3 Data flow
```
App ──GET /home──▶ API ──(cache hit)──▶ Redis/memory ──▶ response (≈20 ms)
                    │
                    └─(miss)──▶ Postgres: categories counts (indexed by geohash cell),
                                rails (indexed queries on Product: categoryId, isAvailable,
                                createdAt, storeId), stores open-now ──▶ fill cache 60 s
App ──GET /me/home-personal──▶ API ──▶ Postgres (active order, drops badge)  (≈30 ms)
Media ──────────────────────────────▶ Cloudinary CDN (sized f_auto/q_auto, HLS)
```

### 5.4 Errors and offline
- The app keeps the last Home response on disk and renders it at once, then refreshes; a stale banner appears only after 10 min offline.
- Each section fails independently: a failed rail is skipped, never a full-screen error.
- Skeletons match the final layout exactly, so content doesn't jump in.

## 6. Scale and reliability

| Users | Home opens/day | Peak req/s to /home | DB load after cache (hit ≥ 90 %) | What to run |
|---|---|---|---|---|
| 10 k DAU | 30 k | ~4 | < 1 q/s | 1 API instance, in-memory cache |
| 1 M DAU | 3 M | ~350 | ~35 q/s | 3–6 instances, Redis, CDN in front of `/home` |
| 10 M DAU | 30 M | ~3 500 | ~350 q/s (read replicas) | autoscaling, Redis cluster, Postgres read replicas, search on OpenSearch or Meilisearch |

Assumptions: 3 Home opens per user per day, peak hour = 10 % of the day and 3× the average within it. Product search stays on Postgres (full text + trigram) up to about 1 M products, then moves to a dedicated search engine. Monitoring: p95 latency of `/home` and the cache hit ratio, with alerts at p95 > 300 ms or hit < 80 %.

## 7. How we know it works (product metrics)

| Metric | Why | Target after redesign |
|---|---|---|
| Home → product view rate | the main job of Home | +20 % vs current |
| Time to first tap on Home | ease of use | < 4 s median |
| Category tile usage | is the new Home understood | > 35 % of sessions |
| Add-to-bag per session | commercial outcome | up |
| Drops tab visits per weekly user | check we didn't hurt video | ≥ 80 % of the current level |
| Drops → product view rate | does video sell | tracked, by store |

Plus qualitative evidence: 5-person usability tests per round ("find a black dress in size M for tonight", "find a vegan lipstick", "watch a video from a shop near you and buy the item").

## 8. Trade-offs

| Decision | Gain | Cost | Why we accept it |
|---|---|---|---|
| Drops only in their own tab | a faster, clearer Home; no video on the main screen | less passive video discovery | mitigated by the dot, store and product entry points, and metrics |
| Server-driven Home | change Home without app releases; A/B tests | more API work and a section contract to maintain | the standard at Wolt, Zalando and Airbnb scale |
| Rule-based ranking first | explainable and legally safe | less personal | personalisation later, consent-based |
| Geohash cache | very cheap at scale | stock counts up to 60 s old | fine for browsing; checkout always rechecks stock |

## 9. Revisit as we grow
- Personalised rails, with consent and an "Why am I seeing this?" sheet.
- Moving search to a dedicated engine at about 1 M products.
- Video live shopping inside Drops.
- A "For you" Drops feed vs "Following": keep both, test the default.
- Store app web dashboard for shops with big catalogues.
