# ADR-001: A professional engineering baseline for Malvoya

**Status:** Proposed
**Date:** 2026-10-22
**Deciders:** Owner (product), lead engineer

## Context

Malvoya has three Flutter apps (customer 91 Dart files, store 50, courier 44), a Node/Express/TypeScript API with Prisma on Render Frankfurt, and a React admin. The feature set is broad and the backend is well tested (672 e2e checks). The way the apps are *engineered*, though, is still a prototype's:

| Finding (checked 2026-10-22) | Why a professional team would care |
|---|---|
| No CI at all (`.github/workflows` missing). Every APK/AAB is built by hand on one Windows PC | A build depends on one machine; a pub.dev DNS blip or a crashed Gradle daemon has already broken two releases |
| 0 Flutter tests in all three apps | Every UI change is verified only by `flutter analyze`; nothing proves checkout, the courier flow or 428 handling actually work |
| No shared Dart code. `api_client.dart`, the theme, haptics, server-error translations, agreements, forgot-password and app gate exist three times | Each fix has to be made three times and the copies already drift (three different error-translation files of 45–70 messages) |
| Oversized screens: `courier_dashboard.dart` 3 181 lines, `vendor_dashboard.dart` 2 018, `checkout.dart` 1 179 | Hard to review, test or change safely; rebuilds more of the screen than needed |
| State is `provider` plus `setState` in large widgets; the customer app also lists `flutter_bloc` | No single pattern for async state, loading, errors and caching |
| No crash reporting or product analytics in the apps | After launch, problems on real phones are invisible |
| UX decided by agents and reviews, never tested with real people | The single biggest risk to "people love it" |

Constraints: a one-person company with no revenue yet, so cost and maintenance burden matter as much as quality. The GitHub repository is public, so secrets must never enter CI logs. Google Play needs signed AABs, and later the App Store needs macOS builds.

## Decision

Adopt a **modular monolith backend** (keep as is) and a **monorepo with shared Flutter packages**, protected by CI and a test pyramid. Make the changes incrementally, without a rewrite.

1. **Shared packages** in `packages/`:
   - `malvoya_core`: API client with session refresh, Accept-Language, X-App-Version and the 428 hook; auth; agreements; app gate; server-message translations; haptics; image URL sizing.
   - `malvoya_ui`: the Birch Market design system, with tokens, typography, buttons, sheets, skeletons, empty states and motion helpers.
   Each app depends on them by path. The duplicated code is deleted from the apps.
2. **Feature-first folders** inside each app (`features/checkout/{data,state,widgets}`). Large screens are split into small widgets with a state class each. State standard: `provider` + `ChangeNotifier`/`ValueNotifier`, already used everywhere, documented in one page. `flutter_bloc` is removed unless it is actually in use.
3. **Test pyramid.**
   - Unit tests for money, dates, slots, unit prices and translations.
   - Widget tests for every sheet and form.
   - Golden (screenshot) tests for key screens in light, dark and Finnish.
   - An `integration_test` happy path per app (browse → bag → pay with Stripe test mode; store accepts; courier delivers) against the local e2e backend.
   - Target: every PR adds tests for what it touches.
4. **CI on GitHub Actions** (free for public repositories).
   - On every push: `flutter analyze` and `flutter test` for all apps, backend build plus the full e2e with Postgres and stripe-mock as services, and the admin build.
   - On a tag: build signed AABs. The signing key is a GitHub encrypted secret that only the owner enters. Upload to the Play internal track with fastlane.
   - iOS later through Codemagic.
5. **Release practice.**
   - Semantic versions, and a CHANGELOG.
   - Play staged rollout (internal → closed → 10 % → 100 %).
   - Feature flags through the existing `/app-config`.
   - The minimum-build gate for breaking API changes.
   - Never deploy a backend change that older apps can't handle. The 428 agreements change is the current example: it is held until the apps that handle it are released.
6. **Observability.**
   - Firebase Crashlytics in the apps (free).
   - Sentry for the API (optional env, being built).
   - Privacy-respecting product analytics only after consent, with a small event list: view item, add to bag, checkout start, paid, delivered.
7. **Real UX research.**
   - Before Play production: moderated usability tests with 5 shoppers, 3 shop owners and 3 couriers per round, on real phones, task-based (find a dress in your size and order it for tonight; add a lipstick with 6 shades; deliver an order). The fixes go into the next sprint.
   - Accessibility audit (WCAG 2.1 AA: contrast, touch targets, screen reader).
   - Repeat every major release.

## Options Considered

### Option A: Keep the current way of working
| Dimension | Assessment |
|---|---|
| Complexity | Low now, rising fast |
| Cost | €0 |
| Scalability | Poor: every change costs ×3 and ships untested |
| Team familiarity | High |

**Pros:** no migration work; agents can keep adding features.
**Cons:** regressions reach users; releases depend on one PC; no visibility after launch; drift between apps grows.

### Option B: Incremental professional baseline (chosen)
| Dimension | Assessment |
|---|---|
| Complexity | Medium: packages, CI and tests, done step by step |
| Cost | €0–25/month (GitHub Actions free for public repos, Crashlytics free; Sentry free tier) |
| Scalability | Good for a small team and millions of users; matches how Wolt-sized teams structure Flutter apps |
| Team familiarity | High: same Flutter, Node and Prisma stack |

**Pros:** one fix lands in all three apps; every change is proven by tests before release; signed builds come from CI, not a laptop; crashes are visible.
**Cons:** 1–2 weeks of engineering before new features resume; tests must be maintained; CI secrets need careful setup by the owner.

### Option C: Rewrite as one super-app, or switch framework (React Native, native)
| Dimension | Assessment |
|---|---|
| Complexity | High |
| Cost | Months of work |
| Scalability | Not better than B |
| Team familiarity | Low |

**Pros:** a single codebase for one app.
**Cons:** throws away working, tested features. Three role-specific apps are the industry norm (Wolt, Uber and Foodora all ship separate customer, merchant and courier apps), because each has different permissions, store listings and review rules. Rejected.

### Backend: microservices vs. modular monolith
Microservices are rejected for now: one developer, one database, and traffic far below what needs splitting. The API is already a modular monolith (`src/modules/*`). Scaling follows the scale work in progress: several instances behind Redis, a background worker, read replicas. Extracting a module into its own service stays possible later, for example media processing or dispatch.

## Trade-off Analysis

The real trade is about two weeks of no visible new features in exchange for every later week being faster and safer. With zero app tests and no CI, each new feature adds risk faster than it adds value. Shared packages remove the largest source of waste (triple maintenance). CI removes the single-PC failure mode that has already cost two releases. Usability tests matter most: features chosen by reviews alone are guesses until real shoppers, shop owners and couriers try them.

## Consequences

- **Easier:** fixing a bug once for all apps; reviewing small widgets; proving a release works; shipping from any machine; seeing crashes; onboarding a second developer.
- **Harder:** every change now needs tests; CI must stay green; package changes need care because they affect three apps.
- **To revisit:** a state-management upgrade (e.g. Riverpod) if async state grows complex; splitting the API when one module dominates load; design tokens in Figma once a designer joins (the Figma connector needs authorising first).

## Action Items

1. [ ] Create `packages/malvoya_core` and `packages/malvoya_ui`; move the duplicated code; apps depend on them by path
2. [ ] Split `courier_dashboard.dart`, `vendor_dashboard.dart` and `checkout.dart` into feature folders
3. [ ] Add unit, widget and golden tests; one `integration_test` happy path per app
4. [ ] GitHub Actions: analyze + test (apps), build + e2e (backend), build (admin) on every push
5. [ ] Release workflow: signed AAB on tag, fastlane to the Play internal track (the owner adds the keystore as a GitHub secret)
6. [ ] Crashlytics in all apps; consented analytics event list
7. [ ] Remove `flutter_bloc` from the customer app if unused
8. [ ] First usability round: 5 shoppers, 3 shop owners, 3 couriers, on 1.8.0; fixes in the next sprint
9. [ ] Accessibility audit (WCAG 2.1 AA) of the key flows
