# Birch Market design system

One look, one token set and one component library for the three Malvoya apps: customer (Malva),
store (Moss) and courier (Lingon). It follows the audit of 22 Oct 2026
([audit-2026-10-22.md](audit-2026-10-22.md)) and ADR-001 ([../adr/ADR-001-engineering-baseline.md](../adr/ADR-001-engineering-baseline.md)).
Public systems used as references: Wolt (one token set for consumer, merchant and courier apps,
skeletons that match the layout, motion only on state changes), Zalando (strict spacing grid,
small type scale, one filter pattern), Material 3 (roles, 48 dp targets, contrast, motion curves).

## Packages

```
packages/
  malvoya_ui/                 the design system (Flutter package)
    lib/malvoya_ui.dart       barrel: import 'package:malvoya_ui/malvoya_ui.dart'
    lib/src/tokens/           colors.dart (MPalette, MalvoyaBrand, MalvoyaColors, MalvoyaPastels)
                              type.dart (MFonts, MTextSize, MType) · layout.dart (MSpace, MRadius,
                              MElevation, MMotion, reduceMotion, kMinTouchTarget) · tokens.dart
                              (MalvoyaTokens ThemeExtension, context.mColors / mTokens / mPastels)
    lib/src/theme/            theme.dart (buildMalvoyaTheme) · fonts.dart (registerMalvoyaFontLicenses)
    lib/src/components/       MButton, MTextField, showMSheet/MSheet/MSheetHandle, MChip/MFilterBar,
                              MSkeleton (+ presets), MStateMessage + MEmptyArt, MSnack, MPrice/MUnitPrice,
                              MBadge, MListTile, MSectionHeader, MSwipeConfirm, MSwatch/MSwatchPicker,
                              MSizeSelector, GoogleLinkTile, BrandMark/BrandTile, Pressable/Bump/AnimatedEuro
    fonts/, assets/licenses/  Hanken Grotesk + Bricolage Grotesque (OFL), bundled, never from the network
    example/                  the gallery app (every component; light/dark, EN/FI, text 1.3, three brands)
    test/                     widget tests + golden tests (test/goldens/*.png)
  malvoya_core/               shared infrastructure (Flutter package, no UI except AppGate)
    lib/malvoya_core.dart     barrel: import 'package:malvoya_core/malvoya_core.dart'
    lib/src/api/              ApiClient, ApiConfig, ApiResult, ApiSession
    lib/src/i18n/             AppLanguage (+ tr, isFinnish, localized, asInt), LocaleProvider,
                              ServerMessages (one merged fi table)
    lib/src/format/           money.dart (formatEuro, euro, UnitPrice) · dates.dart
    lib/src/agreements/       AgreementsApi + AgreementRequired/AgreementDoc/AgreementState/…
    lib/src/media/            sizedImageUrl (Cloudinary sizing)
    lib/src/platform/         Haptics, AppGate, legalUrl/openLegal
    test/                     money, unit price, dates, translations, URL sizing, API client (428, 401, retries)
tool/check_tokens.dart        token lint (see "Token lint")
```

Each app depends on both by path (`malvoya_core: {path: ../packages/malvoya_core}`, same for
`malvoya_ui`). The app's `lib/config/theme.dart` is now a thin adapter (`AppTheme`) whose values all
come from the design system, so existing screens kept compiling while they move to tokens.

### Setting up an app

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMalvoyaFontLicenses();                 // OFL texts on the licences page
  ApiConfig.baseUrl = AppConstants.apiBase;      // per app
  ApiConfig.onNetworkError = ConnectivityService.instance.verify;   // store, courier
  ApiConfig.onAgreementRequired = Agreements.instance.handleRequired; // customer: 428 → sheet → retry
  await AppLanguage.loadAppVersion();            // X-App-Version
  runApp(MaterialApp(
    theme: buildMalvoyaTheme(brand: MPalette.moss, brightness: Brightness.light, style: MalvoyaThemeStyle.tool),
    highContrastTheme: buildMalvoyaTheme(brand: MPalette.moss, brightness: Brightness.light, style: MalvoyaThemeStyle.tool, highContrast: true),
    builder: (context, child) => AppGate(app: 'store', child: child!),
    …
  ));
}
```
`AuthService` implements `ApiSession` (access token + `refreshSession`) and `GoogleLinkAccount`.

## Tokens

All theme-dependent tokens travel in the theme as the `MalvoyaTokens` extension:
`MalvoyaTokens.of(context)`, or the shortcuts `context.mColors`, `context.mPastels`, `context.mTokens.shadow(MElevation.e2)`.
Spacing, radii, type and motion are plain constants.

### Colour roles (`MalvoyaColors`)

Every `on…` colour is AA (4.5:1) on its partner. Screens use roles, never raw palette values; the
palette (`MPalette`) is for the few fixed colours (white markers over photos, map dots) and for the
apps' `AppTheme` adapters.

| Role | Light | Dark | Use |
|---|---|---|---|
| background | Birch `#F6F3EE` | `#121015` | screen background |
| surface / onSurface | white / ink `#1C1820` | `#221C29` / Birch | cards, sheets, dialogs / body text |
| surfaceVariant / onSurfaceVariant | sand `#F3EEE6` / `#6B6472` | `#2A2331` / `#B9AFC2` | inputs, quiet tiles / secondary text |
| outline / outlineStrong | `#EDE6DA` / `#7A7268` | `#332B3B` / `#A79EAF` | hairlines / borders that must be seen |
| primary / onPrimary | brand / white | brand tint (Malva `#C9A3DD`, Moss `#8FD5AE`, Lingon `#F4A08F`) / deep brand | the app accent |
| primarySoft / onPrimarySoft | brand soft (lilac, `#E4EFE9`, peach) / brand | brand 25 % / brand tint | selected chips, icon circles |
| sunshine / onSunshine | `#F2C14E` / ink | same | highlights, active tab, counters |
| sunshineSoft / onSunshineSoft | `#FDF1D8` / `#6A4500` | `#3A3020` / `#F7D98A` | tips, notices |
| success (+Soft) | `#248A52`, mint / `#1B6B40` | `#5BC48A`, `#1E3A2A` | paid, delivered, open |
| warning (+Soft) | `#E08A00`, `#FDF1D8` / `#6A4500` | `#F0A63A`, `#3A3020` | needs attention soon |
| danger (+Soft) | `#D93025`, `#FDECEA` / `#B3261E` | `#FF6B5E`, `#3A1F22` / `#FFB4AB` | errors, destructive |
| sale | Lingon `#C2412D` | `#FF8A73` | reduced prices (real Omnibus reference only) |
| inverseSurface | Night `#17131C` | `#3A3242` | snackbars, the floating tab bar |

Brands: `MalvoyaBrand.malva` (customer), `.moss` (store), `.lingon` (courier), each with
hand-tuned `strong`, `soft`, `dark` and `onDark`. `buildMalvoyaTheme(brand: …)` looks the brand up;
any other colour gets derived companions. `MalvoyaColors.warmDark()` is the customer's "eye comfort" mode.

**Pastels** (`MalvoyaPastels`, `context.mPastels`): lilac `#F1E7F6`, mint `#E3F2E9`, peach `#FBEAE6`,
sand `#F3EEE6`, clay `#E9DFD2` (+ clayInk `#8A6F55`). In dark mode each becomes a 22 % tint of its hue.

**Fixed palette colours** with a meaning of their own: `MPalette.white` (light surfaces, text on brand
fills, markers over maps and photos), `scrim` (54 % black), `mediaScrim`/`mediaScrimSoft` (gradients
over video), `like` (heart over media), `locationBlue` ("you are here" on maps).

### Type scale (`MType`, `MTextSize`)

| Token | Size | Face | Use |
|---|---|---|---|
| displayL | 32 | Bricolage 800 | hero numbers, onboarding |
| displayM | 26 | Bricolage 800 | screen headlines |
| displayS | 22 | Bricolage 800 | sheet and section headlines |
| title | 18 | Bricolage 700 | card titles, app bar (the app bar keeps 19) |
| bodyL | 16 | Hanken 400, 1.45 | body copy, buttons |
| bodyM | 14 | Hanken 400, 1.4 | secondary copy, list subtitles |
| label | 13 | Hanken 700 | chips, badges, small buttons |
| caption | 12 | Hanken 500 | fine print, hints, timestamps |

Styles carry no colour (they inherit). Use `MType.bodyM.copyWith(color: c.onSurfaceVariant)` for new
text, `fontSize: MTextSize.label` to put an existing style on the scale. All sizes follow the phone's
text size. Fonts are referenced as `MFonts.body` / `MFonts.display` (`packages/malvoya_ui/…`).

### Spacing, radii, elevation, motion

* `MSpace`: `xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · x3l 32 · x4l 40` (4-pt grid).
* `MRadius`: `xs 8 · sm 12 · md 16 · lg 24 · pill`, with `brXs…brLg`, `pillRadius`, `sheetTop`.
* `MElevation.e1/e2/e3.shadows(brightness:)`: resting, raised, floating. Warm and soft; dark mode
  uses borders (only e3 keeps a faint shadow).
* `MMotion`: `fast 150 ms`, `base 240 ms`, `slow 400 ms`; curves `standard` (M3 standard) and
  `emphasised` (M3 emphasised decelerate). `MMotion.of(context, d)` and `reduceMotion(context)`
  return zero / true when the phone asks for less motion. Animate state changes only.
* `kMinTouchTarget = 48`.

### Theme (`buildMalvoyaTheme`)

`buildMalvoyaTheme({required Color brand, required Brightness brightness, MalvoyaThemeStyle style = shop, bool highContrast = false, MalvoyaColors? colors})`
builds the full ThemeData: Material 3 colour scheme from the roles, the text theme from the scale,
pill buttons with theme minimum `Size(64, 54)` (buttons size to their content; full-width buttons ask
for it; **never `Size.fromHeight` in theme-level styles**), sand-filled inputs with a brand focus ring,
snackbars, sheets (drag handle on), dialogs, cards, chips, navigation, switches and checkboxes, and
Android's predictive-back page transitions. `style: tool` (store, courier) keeps their start-aligned
titles, quieter body text and tinted chips; `shop` (customer) centred titles and outlined chips.
`highContrast` strengthens secondary text, lines and field borders (`MaterialApp.highContrastTheme`).

## Components

Every component reads the tokens (so it is right in dark mode and in all three brands), has a 48 dp
touch target, scales with text size without overflowing (labels wrap instead), respects reduce
motion, and exposes clean semantics. They are shown in the gallery (`packages/malvoya_ui/example`)
and covered by goldens in four variants (light EN, dark EN, light FI, text 1.3).

### MButton
The pill button. One primary action per screen.
* **Variants** `MButtonVariant.primary | secondary | outline | danger | text`; **sizes** `sm (40, 48 dp target) | md (54) | lg (60)`.
* **Props** `label`, `onPressed`, `variant`, `size`, `icon`, `trailingIcon`, `loading`, `expand`, `semanticLabel`.
* **States** default, pressed (0.97 press scale; still with reduce motion), focused, disabled (`onPressed: null`),
  loading (spinner in place of the label; width and colours kept; taps ignored).
* **Accessibility** one node: "Pay, button"; loading adds the value "Working" and reports disabled.
* **Do** use `expand: true` for bottom actions; pass `loading` instead of swapping the button for a spinner.
  **Don't** put two primary buttons side by side; don't set `Size.fromHeight` on it.
```dart
MButton(label: tr(context, 'Pay', 'Maksa'), icon: Icons.lock_rounded, expand: true, loading: _paying, onPressed: _pay)
```

### MTextField
Filled field (sand, 16 px corners, brand focus ring).
* **Props** `controller`, `label`, `hint`, `helper`, `errorText`, `prefixIcon`, `suffix`, `obscure`, `enabled`,
  `readOnly`, keyboard/autofill/formatter options, `maxLines`, `maxLength`, `onChanged`, `onSubmitted`.
* **States** default, focused, filled, disabled, error (red border + message, announced). `obscure` adds a 48 dp show/hide button.
* **Do** keep the label (it floats, so it stays readable); write errors as a fix ("Use 5 digits"). **Don't** use the hint as the only label.
```dart
MTextField(label: tr(context, 'Email', 'Sähköposti'), keyboardType: TextInputType.emailAddress, errorText: _emailError)
```

### showMSheet / MSheet / MSheetHandle
Bottom sheets with the drag-handle rule built in.
* `showMSheet(context, builder:, transparent: false, isScrollControlled: true, useSafeArea: true, …)`: a solid sheet uses the
  theme surface and the theme handle; `transparent: true` switches the theme handle off (`showDragHandle: false`), because the
  sheet draws its own shape. `MSheet(handle: true)` draws that surface and the standard `MSheetHandle`.
* `MSheet` props: `title`, `subtitle`, `child`, `actions` (pinned under the content), `handle`, `padding`; pads for the keyboard.
* **Do** use `MSheet` for confirmations and pickers. **Don't** draw a handle inside a solid sheet (two handles), or show a
  transparent sheet without one.
```dart
showMSheet(context, transparent: true, builder: (ctx) => MSheet(handle: true, title: 'Start a new bag?', actions: [MButton(label: 'New bag', expand: true, onPressed: …)], child: Text(…)))
```

### MChip and MFilterBar
* `MChip(label, selected, onSelected, icon, count, onRemove, showCheck)`: toggle / choice / active-filter chip; selected =
  soft brand fill, brand border, check mark; `onRemove` adds a × ("Remove M" tooltip). 36 px pill in a 48 dp target.
* `MFilterBar(quick, onQuickChanged, active, onRemove, onClearAll, onOpenFilters, sortLabel, onSort)`: the one filter
  pattern for lists: "Filters (n)", sort, quick toggles, active filters as removable chips and "Clear all" (from two).
  Scrolls horizontally, never wraps or overflows.
* **Do** show every active filter so it can be removed in one tap. **Don't** hide the sort inside the filter sheet.

### MSkeleton
* `MSkeleton(child)` shimmer wrapper (still with reduce motion; one "Loading" for screen readers, live region),
  `MSkeletonBox(width, height, radius)`, presets `MSkeletonCard(thumbnail, thumbHeight, lines, button)`,
  `MSkeletonList(count, thumbnail, …)` (pull-to-refresh capable), `MSkeletonProductTile`, `MSkeletonProductGrid`, `MSkeletonDetail`.
* **Do** match the final layout (Wolt). **Don't** show a full-screen spinner for lists.

### MStateMessage and MEmptyArt
* `MStateMessage(kind: empty|error|offline, message, title, icon, art, actionLabel, actionIcon, onAction, action, scrollable, top, centered)`,
  plus `MStateMessage.error(message?, onRetry)` and `.offline(…)` with default bilingual sentences.
* Uses the illustrated `MEmptyArt` scenes (bag, orders, favourites, search, offline, store, drops, delivery; `MEmptyArt.forIcon`
  picks one from a Material icon), otherwise an icon in a soft circle. Errors are live regions. Scrollable by default so it works
  inside a `RefreshIndicator`; `scrollable: false` inside lists.
* **Do** say what to do next ("Browse shops"). **Don't** blame the user or show raw error codes.

### MSnack
* `MSnack.show(context, message, kind: success|info|error, actionLabel, onAction, duration)`, `MSnack.success`, `MSnack.error`,
  `MSnack.build` (for a messenger kept outside the tree). A floating dark pill with a coloured icon; replaces the visible snack;
  errors stay 6 s.
* **Don't** use a snack for something the user must act on.

### MPrice and MUnitPrice
* `MPrice(cents, previousCents, discountPct, size: sm|md|lg, color, showReferenceLabel, unitPrice, prefix)` and
  `MPrice.fromPricing(pricingMap, overrideCents:)`. Shows a reduction only when the API sent a reference price (Omnibus: lowest
  of the 30 days before); never computes discounts. "49,90 €" (fi) / "€49.90" (en). Screen readers hear "€39.90, before €49.90".
* `MUnitPrice(UnitPrice)` / `MUnitPrice.forContent(priceCents, amount, unit)`: "178,00 €/l" under the price (per litre or
  kilogram, never per 100 ml/g; none under 50 ml/50 g or for pieces), computed like the API's `catalog/unitPrice.ts`.

### MBadge
`MBadge(label, tone: brand|sunshine|success|warning|danger|neutral, icon, strong, semanticLabel)`, `MBadge.count(n)` (99+).
Describes, never taps. Soft tones use their `on…` colours.

### MListTile and MSectionHeader
* `MListTile(title, subtitle, icon | leading, trailing, onTap, chevron, destructive, enabled, iconBackground)`: ≥ 56 px, icon
  in a soft circle, wraps long titles, destructive rows in danger.
* `MSectionHeader(title, subtitle, actionLabel, onAction)`: a header for screen readers, optional "See all".

### MSwipeConfirm
The courier's slide-to-confirm for irreversible steps (picked up, delivered). `label`, `onConfirmed`, `icon`, `busy`, `enabled`, `color`.
Fires past `MSwipeConfirm.threshold` (80 %), snaps back otherwise (instantly with reduce motion), strong haptic on confirm. With
TalkBack/VoiceOver or switch access it is a plain button with the same label.

### MSwatch and MSwatchPicker
Beauty shades (Sephora / Lyko pattern). `MSwatch(color, name, selected, soldOut, onTap, size)`: the real colour in a circle, a
brand ring with a gap when chosen, a hairline for light shades, a diagonal line when sold out (not selectable, announced
"Berry 03, sold out"). `MSwatchPicker(options, selectedId, onChanged, label)` shows "Shade: Rose 02" so colour is never the only cue;
`MSwatchOption.fromVariant(apiVariant)` reads `shadeHex`/`shadeName`/`inStock` (API 2.12).

### MSizeSelector
`MSizeSelector(options: [MSizeOption(id, label, soldOut)], selectedId, onChanged, label, onSizeGuide)`: "Size" with a
"Size guide" link, then the customer app's size tiles (≥ 60 × 48, soft brand fill and 2 px border when chosen, sold out crossed
out and not selectable). Wraps to more rows so every size is visible.

### Also in the package
`GoogleLinkTile(account:)` (link/unlink Google; the apps' `AuthService` implements `GoogleLinkAccount`), `BrandMark`/`BrandTile`
(the Thread M), `Pressable` (press scale), `Bump` (pop on change), `AnimatedEuro` (counting money), `colorFromHex`.

## malvoya_core

* **ApiClient** (`const ApiClient(auth)`): base URL from `ApiConfig.baseUrl`; adds the session, `Accept-Language` and
  `X-App-Version`; 15 s timeout (`ApiConfig.timeout`); refreshes the session once on 401 and repeats; on 428
  `AGREEMENT_REQUIRED` asks `ApiConfig.onAgreementRequired` and repeats once (never loops); repeats GETs once after a network error
  or 502/503/504 (never other methods); `ApiConfig.onNetworkError` hook. `ApiResult`: `status`, `data`, `error` (app language),
  `rawError` (as sent), `errorText(context)`, `errorMessage`, `agreementRequired`, `notice`/`withNotice`.
* **ServerMessages.localize(message)**: one merged Finnish table (the union of the three apps' 45/55/70-message tables plus the
  client's own sentences, de-duplicated: 150+ exact messages and 9 patterns); bilingual "fi. / en." server sentences are split.
* **AppLanguage** (code, `headers`, `pick`, `loadAppVersion`), `tr`, `isFinnish`, `localized`, `asInt`; **LocaleProvider**
  (saved choice, optional system fallback, `onUserChange`).
* **Money and dates**: `formatEuro`/`euro`, `UnitPrice.compute/fromJson/format`, `formatDate`, `dateText`, `dateTimeText`,
  `scheduledWindow`, `etaWindow`, `parseApiDate`.
* **Agreements data layer**: `AgreementsApi.load / versions / accept / copyLink`, `AgreementRequired.from(res)`, `AgreementDoc`,
  `AgreementState`, `AgreementVersion`, `AgreementAcceptResult`, `agreementTitle`, `AgreementDocs`. The sheets stay per app (each
  role has its own summary and wording).
* **Haptics** (`selection`, `light`, `medium`, `success`, `strong`, `warning`, `sequence`), **sizedImageUrl**, **AppGate**,
  **legalUrl / openLegal**.

## Testing

```bash
cd packages/malvoya_core && flutter test          # 37 unit tests
cd packages/malvoya_ui && flutter test            # 16 widget tests + 15 golden tests
cd packages/malvoya_ui && flutter test --update-goldens   # after an intended visual change; review the PNGs
```
Goldens load the bundled fonts and Material icons, so the PNGs show the real type. They are
rendered on Windows; on another OS small anti-aliasing differences can fail them (regenerate there, or
run goldens on one CI platform only).

## Token lint

`dart tool/check_tokens.dart` lists hex `Color(0x…)` literals, `fontSize:` literals and `Colors.*`
uses (except `Colors.transparent`) outside `packages/malvoya_ui`, ignoring comments and strings.
`--list` prints every finding, `--baseline` fails (exit 1) when an app has more than
`tool/token_baseline.json` allows (the CI ratchet), `--update-baseline` lowers the ceiling.

| App | hex before → after | fontSize before → after | Colors.* before → after | total before → after |
|---|---|---|---|---|
| customer | 225 → 1 | 383 → 1 | 230 → 0 | 838 → 2 |
| store | 85 → 0 | 180 → 1 | 99 → 0 | 364 → 1 |
| courier | 72 → 0 | 138 → 0 | 93 → 0 | 303 → 0 |
| **all** | 382 → 1 | 701 → 2 | 422 → 0 | **1505 → 3** |

The three that remain are deliberate: Google's brand blue on the "Sign in with Google" button
(their guideline), and a 1 px transparent text used by the forgot-password sheets as an autofill
anchor. Outside the lint, the same pass moved spacing, radius and motion values that were exactly on
the scale to tokens: EdgeInsets with literal numbers 334/239/173 → 151/120/72 (customer/store/courier;
the rest are off-scale values such as 6, 10, 14, 18), `Radius.circular` literals 208/79/59 → 99/49/33.

## Migration status (2026-10-22)

**Done in all three apps**
* Depend on both packages; fonts and OFL texts come from `malvoya_ui` (the apps' 24 font files and 6 licence copies deleted).
* `config/theme.dart` → `buildMalvoyaTheme` adapter; customer light, dark, high contrast and eye comfort; store and courier light
  and high contrast in the `tool` style.
* Duplicated files deleted (37): customer `core/{api_client, app_gate, app_language, font_licenses, haptics, image_url,
  legal_links, strings, google_link_tile}.dart`, `locale_provider.dart`, `widgets/{brand_mark, empty_art, motion, price_tag,
  skeleton}.dart`; store `core/{api_client, app_gate, font_licenses, haptics, legal_links, server_errors, google_link_tile}.dart`,
  `locale_provider.dart`, `widgets/{brand_mark, loading_states}.dart`; courier `core/{api_client, app_gate, app_version,
  font_licenses, haptics, legal_links, server_messages, strings, google_link_tile}.dart`, `locale_provider.dart`,
  `widgets/{brand_mark, swipe_to_confirm}.dart`. App-specific remnants: customer `core/account_language.dart` (saves the
  language on the account), store `core/strings.dart` (`commissionText`), store `widgets/error_banner.dart`, courier
  `widgets/skeletons.dart` (job/delivery/earnings shapes built from `MSkeleton`).
* Agreements: each app's data calls go through `AgreementsApi`; the customer's 428 hook is `ApiConfig.onAgreementRequired`;
  store `withAgreement` and courier `Agreements.resolve` read `AgreementRequired`. Sheets unchanged in wording.
* All 50 convertible bottom sheets use `showMSheet` (transparent ones without the theme handle; three customer sheets that drew a
  second handle on top of the theme's now show one); hand-drawn grey handles replaced by `MSheetHandle`.
* Empty/error/loading states use `MStateMessage` and `MSkeleton`; price tags use `MPrice`; the courier's swipe uses
  `MSwipeConfirm`; 28 ad-hoc "spinner instead of label" buttons (login, register, checkout pay, agreement accept, forgot
  password, product editor, …) use `MButton(loading:)`; 74 plain snackbars use `MSnack`.
* Literal → token rules used (also for future screens): hex values → the palette role they were (e.g. `#D93025` → red /
  danger, `#6A4500` and `#8A5A00` → amber ink); font sizes snapped to the scale (≤ 12.5 → caption 12, 13–13.5 → label,
  14–14.5 → bodyM, 15–16 → bodyL, 17–19 → title, 20–22 → displayS, 26–28 → displayM, 30 → displayL), so some text moved by
  ≤ 1 px (15 → 16, 17 → 18; 20 → 22; the 8 px badge labels became 12 for legibility); `Colors.white` → surface or on-brand
  by its role (customer: `onBrand`/`onMedia`, fixed `MPalette.white` where it was a fixed white), greys → outline / secondary
  text (warmer, higher-contrast Birch values), black shadows → Night with the same opacity.
* Radius scale: the old 18 px "md" corner is now 16 (inputs, tiles, snackbars) and 22/28 cards and sheets are 24.

**Deferred**
* Screen-by-screen semantic review of the customer's remaining fixed-white surfaces in dark mode (they are exactly as before;
  some older screens such as the address manager and map picker would look better on `surface`).
* Rebuilding the large screens (`courier_dashboard.dart`, `vendor_dashboard.dart`, `checkout.dart`) from components and splitting
  them (ADR-001 item 2); most of their own small widgets (cards, rows) are still hand-built, now with tokens.
* Moving more shared infrastructure to `malvoya_core`: `auth_service.dart`, `push_service.dart`, `socket_service.dart`, the store
  and courier `connectivity.dart` (identical) and the customer `network_status.dart`, `l10n.dart`; per-app agreement and
  forgot-password sheets could become one `malvoya_ui` sheet with per-role copy.
* `MSwatchPicker` / `MSizeSelector` / `MFilterBar` / `MUnitPrice` are ready but the customer product page still uses its existing
  size tiles; wiring them to API 2.12 shades and unit prices waits for that backend release.
* `AppTheme.display(size:)` callers still pass their own heading sizes (not counted by the lint).
* A CI job running `dart tool/check_tokens.dart --baseline`, `flutter analyze` and the package tests (ADR-001 item 4).
