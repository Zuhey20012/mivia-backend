# DESIGN.md: Malvoya "Birch Market"

> The single source of truth for how Malvoya looks, moves and speaks, written so any designer or AI coding agent builds screens that feel like Malvoya.
> Values come from the code in `packages/malvoya_ui` (tokens, theme, components). If this file and the code disagree, **the code wins**: fix this file.
> Products: **Malvoya** (shoppers), **Malvoya Store** (shops), **Malvoya Courier** (couriers), the admin panel and the website.

---

## 1. Visual Theme & Atmosphere

**Birch Market.** A warm, sunlit Nordic marketplace: birch-pale ground, ink-dark type, pastel product tiles like stalls at a market, and one bright sunshine accent. It should feel **friendly, calm and local**, closer to a well-kept neighbourhood boutique than a discount warehouse.

- **Mood:** soothing, playful in small doses, trustworthy. Never loud, never "tech dark" by default.
- **Personality:** local, honest, quick. Fashion and beauty with care, not hype.
- **Signature elements:**
  - the **Thread M** mark;
  - the **sunshine dot**;
  - **stadium (pill) buttons**;
  - **pastel category tiles**;
  - soft paper-like elevation;
  - motion that draws, glides and settles.
- **One brand colour per app:** Malva (shoppers), Moss (shops) and Lingon (couriers), always paired with the shared sunshine accent.

---

## 2. Color Palette & Roles

### Brand
| Token | Hex | Role |
|---|---|---|
| `malva` | `#6D2E8C` | Customer app brand: primary buttons, active states, the travelled route line |
| `malvaStrong` | `#55226E` | pressed and hover state of Malva |
| `malvaOnDark` | `#C9A3DD` | Malva on dark surfaces |
| `moss` | `#2E6B4F` | Store app brand |
| `mossStrong` | `#245740` | pressed Moss |
| `mossSoft` | `#E4EFE9` | soft Moss fill |
| `mossOnDark` | `#8FD5AE` | Moss on dark |
| `lingon` | `#C2412D` | Courier app brand |
| `lingonStrong` | `#9E3222` | pressed Lingon |
| `sunshine` | `#F2C14E` | shared accent: the active tab pill, the brand dot, highlights, celebration. **Never body text** |
| `sunshineLight` | `#FDF1D8` | soft sunshine fill (notes, banners) |

### Neutrals (light)
| Token | Hex | Role |
|---|---|---|
| `birch` | `#F6F3EE` | app background, the Birch ground |
| `white` | `#FFFFFF` | cards, sheets, inputs |
| `sand` | `#F3EEE6` | subtle section fill |
| `clay` | `#E9DFD2` | warm neutral fill |
| `clayInk` | `#8A6F55` | text on clay |
| `line` | `#EDE6DA` | hairlines, card borders |
| `lineStrong` | `#7A7268` | strong dividers, outlined controls |
| `ink` | `#1C1820` | primary text |
| `inkSecondary` | `#6B6472` | secondary text (≥ 4.5:1 on birch) |

### Neutrals (dark)
| Token | Hex | Role |
|---|---|---|
| `nightBackground` | `#121015` | dark app background |
| `nightSurface` | `#221C29` | cards and sheets |
| `nightSurfaceVariant` | `#2A2331` | section fill |
| `nightRaised` | `#3A3242` | raised controls |
| `nightLine` / `nightLineStrong` | `#332B3B` / `#A79EAF` | lines |
| `nightInkSecondary` | `#B9AFC2` | secondary text |
| `night` | `#17131C` | the tab bar pill in light mode, the ink bands |

### Pastels: category tiles and illustrations
`lilac #F1E7F6` · `peach #FBEAE6` · `mint #E3F2E9` · `clay #E9DFD2` · `sand #F3EEE6` · `sunshineLight #FDF1D8`. Each category gets one pastel tile with its icon in the matching deeper hue.

### Semantic
| Token | Hex | Use |
|---|---|---|
| `green` / `greenDark` | `#248A52` / `#1B6B40` | success, "open", delivered |
| `amber` / `amberInk` | `#E08A00` / `#6A4500` | warning, "closes soon" |
| `red` / `redInk` / `redLight` / `redLine` | `#D93025` / `#B3261E` / `#FDECEA` / `#FFCDD2` | errors, destructive actions, recalls |
| `like` | `#FF4D6D` | likes in Drops only |
| `locationBlue` | `#2563EB` | the "you are here" dot on maps only |
| `scrim`, `mediaScrim`, `mediaScrimSoft` | black at 54 %, 70 %, 40 % | overlays on sheets and video |

**Rules:**
- Brand colour = action. Sunshine = delight and focus. Semantic colours = state only.
- Text on any fill must reach **4.5:1** (3:1 for large type); use `ink` on sunshine, never white.

---

## 3. Typography Rules

- **Display:** **Bricolage Grotesque** (600 / 700 / 800), bundled; never loaded from a font CDN. Used for headings, prices, ETAs and the wordmark.
- **Body:** **Hanken Grotesk** (400–800), bundled. Used for everything else.

| Token | Font | Size | Weight | Line height | Letter spacing |
|---|---|---|---|---|---|
| `displayL` | Bricolage | 32 | 800 | 1.12 | −0.6 |
| `displayM` | Bricolage | 26 | 800 | 1.12 | −0.5 |
| `displayS` | Bricolage | 22 | 800 | 1.12 | −0.4 |
| `title` | Bricolage | 18 | 700 | 1.12 | −0.3 |
| `bodyL` | Hanken | 16 | 400 | 1.45 | 0 |
| `bodyM` | Hanken | 14 | 400 | 1.4 | 0 |
| `label` | Hanken | 13 | 700 | 1.3 | 0 |
| `caption` | Hanken | 12 | 500 | 1.35 | 0 |

**Rules:**
- Only these eight sizes. Never hard-code `fontSize` outside the package (a CI lint enforces it).
- Prices and countdowns use tabular figures.
- Text must survive **1.3× system text scale** without clipping: wrap or scale down, never cut.
- **Finnish first, English second**, with natural Finnish (e.g. "Kassalle", "Tänään perille", "Lähetti"). Every string goes through `tr()`.

---

## 4. Component Stylings
All from `packages/malvoya_ui`. **Use the component; don't rebuild it.**

- **MButton:**
  - stadium shape, minimum height 54, minimum width 64;
  - variants: `primary` (brand fill, white label), `secondary` (sand fill), `outline` (brand outline), `danger` (red outline or fill; used for every destructive action), `text`;
  - sizes sm/md/lg;
  - `loading` shows a spinner and disables taps; press scale 0.97.
  - Never `Size.fromHeight` in theme-level styles: it breaks buttons inside Rows.
- **MTextField:** white field, 16 radius, `line` border, brand focus ring, error text below in red.
- **MSheet / showMSheet:**
  - 24-radius top corners, with a drag handle by default;
  - transparent sheets set `showDragHandle: false` (the component handles it);
  - a title, then content, then one primary action at the bottom.
- **MChip / MFilterBar:**
  - pill chips: selected = ink fill with a birch label, default = white with a `line` border;
  - active filters show as removable chips with an ×, and a sort chip sits at the end.
- **Category tile:**
  - a pastel rounded square (radius 16–24), an icon in the deeper hue, the label below in `label`;
  - 3×3 grid on Home; the tiles stagger in once per session.
- **Product tile:** 4:5 image, 16 radius, price in `title`, unit price in `caption` for beauty items, one status chip at most, the heart in the top-right corner.
- **MPrice / MUnitPrice:** euro formatting in the app language ("12,90 €" in Finnish); the unit price per l or kg under the price.
- **MSwatch / MSwatchPicker:** 40–48 px shade circles, the selected one with an ink ring, sold-out shades crossed; the shade name is always shown as text.
- **MSizeSelector:** pill sizes, with sold out greyed and struck through; a "Size guide" link opens the shop's chart in cm.
- **MSkeleton:** shimmer placeholders that match the final layout exactly. Never a lone spinner on a list.
- **MStateMessage:** illustrated empty, error and offline states with **one** next action ("Browse shops", "Try again").
- **MSnack:** an icon plus a short message; success, info and error tones; it replaces the current one rather than queueing.
- **MSwipeConfirm:** used for irreversible courier steps (picked up, delivered); 80 % threshold; a plain button with screen readers.
- **MBadge, MListTile, MSectionHeader:** consistent paddings from the spacing scale.
- **Tab bar:** a floating night pill, 66 tall, radius 33. The active tab grows into a sunshine pill with its label; the others are icons only.
- **Bag bar:** a floating brand pill above the tab bar, with the count in a sunshine circle and the total, plus a white "Kassalle" button.
- **Signature motion components:** MalvoyaIntro (the Thread M draws, the dot drops), MRefreshIndicator (an M stroke), MSuccessCheck, showMCelebration, MStatusPill (breathes while open), LiveRouteMap (the courier glides along the route).

---

## 5. Layout Principles
- **Spacing scale** (`MSpace`): **4 · 8 · 12 · 16 · 20 · 24 · 32 · 40**. Use only these.
- **Radius scale** (`MRadius`): **8 · 12 · 16 · 24 · pill (999)**. Cards 16, sheets 24 (top), tiles 16–24, buttons pill.
- **Screen gutters:** 16 on phones. Section titles have 24 above and 12 below.
- **Thumb zone:** primary actions in the bottom third; sticky bottom bars for checkout and courier steps.
- **Touch targets:** at least **48 × 48 dp**.
- **One primary action per screen.** Secondary actions are outline or text buttons.
- **Customer Home order:** search → audience switch (All / Women / Men / Kids / Teens) → active order → categories → services row → collections → rails (Delivered today when possible, New in, Second-hand, Gifts) → shops near you. **Drops live in their own tab**, never as a Home tile.
- **Rails:** about 2.5 cards visible, at most 2 items per shop, hidden when fewer than 4 items.
- **Store app home:** open status, then orders waiting, then today, then setup, then returns.
- **Courier home:** the online switch, then the active job, then offers, then today's earnings.

---

## 6. Depth & Elevation
Soft, warm, paper-like shadows tinted with `#3A2A1A`; **no shadows in dark mode** (elevation comes from lighter surfaces).

| Level | Light mode | Use |
|---|---|---|
| `e1` | warm 4 %, blur 8, y 2 | cards, tiles |
| `e2` | warm 6 %, blur 18, y 6 | floating bars, the bag bar |
| `e3` | warm 12 %, blur 28, y 12 | sheets, dialogs |

Borders (`line`) separate more often than shadows do. Never stack more than two elevated layers on screen at once.

---

## 7. Motion
| Token | Value | Use |
|---|---|---|
| `MMotion.fast` | 150 ms | press, toggle |
| `MMotion.base` | 240 ms | most transitions |
| `MMotion.slow` | 400 ms | sheets, larger reveals |
| `standard` curve | cubic(0.2, 0, 0, 1) | default |
| `emphasised` curve | cubic(0.05, 0.7, 0.1, 1) | entrances, celebrations |

**Signature moments:**
- **Intro:** the M draws itself (~0.8 s), the dot bounces in; under 1.4 s in total and skippable.
- **Live route:** the courier glides along the street route (1.2–12 s per update), the travelled line fills in Malva, and the home pin pulses within ~300 m.
- **Paid and delivered moments:** a short sunshine celebration.
- **Pull to refresh:** the M stroke.
- **Open pill:** breathes while accepting orders.

**Rules:**
- Respect **reduce motion** (`MediaQuery.disableAnimations`): no pulses, instant transitions, markers jump.
- Animate with **one controller per animation** and wrap painters in a RepaintBoundary.
- Aim for 60 fps on a mid-range Android.
- Motion explains a change. It never decorates or delays.

---

## 8. Do's and Don'ts

**Do:**
- use `malvoya_ui` tokens and components only;
- show real data, and hide a section when there's none;
- give every empty or error state an illustration and one action;
- write Finnish first and plainly; show the full price (all fees) before payment;
- mark ads as "Mainos / Sponsored";
- use certified claims only, with the certificate shown;
- keep courier pay and ETAs honest ("about 6 min").

**Don't:**
- hard-code colours, font sizes, radii or durations (CI fails);
- load fonts, analytics or session-replay scripts from third parties (CI fails);
- use fake urgency ("only 2 left!" when untrue), fake counters ("12 people viewing"), pre-ticked add-ons or hidden fees;
- use generic green words ("eco-friendly", "sustainable", "vastuullinen"), leaf icons or green coding for products;
- use sunshine as text, or white text on sunshine;
- put more than one primary button in view, or put destructive actions in the brand colour;
- show video or autoplay on Home;
- profile or target ads at under-18s.

---

## 9. Responsive Behavior
- **Phones first:** designed at 360–430 pt wide, and tested at 360.
- **Large text (1.3×):** layouts wrap and tiles grow; nothing clips.
- **Tablets and iPad:** the apps target phones (`TARGETED_DEVICE_FAMILY = 1` on iOS); on Android tablets content stays at a comfortable maximum width, centred.
- **Dark mode:** every screen in both themes; brand colours switch to their `OnDark` variants; no shadows.
- **Website** (`web/`, Astro): mobile-first, flawless at 360 px, light and dark, self-hosted fonts, no cookies or trackers, Lighthouse ≥ 95.
- **Admin panel:** desktop-first, readable on a tablet.

---

## 10. Agent Prompt Guide
When an AI agent builds or changes UI for Malvoya, paste this in:

> Build in the Malvoya **Birch Market** design system. Use only `packages/malvoya_ui`: the tokens `MSpace`, `MRadius`, `MType`, `MMotion` and `context.mColors`, plus the components (MButton, MSheet/showMSheet, MChip, MFilterBar, MSkeleton, MStateMessage, MSnack, MPrice, MUnitPrice, MSwatchPicker, MSizeSelector, MSwipeConfirm, MRefreshIndicator).
> - Background birch `#F6F3EE`, text ink `#1C1820`, the app brand colour for primary actions (Malva `#6D2E8C`, Moss `#2E6B4F`, Lingon `#C2412D`), sunshine `#F2C14E` for accent only.
> - Bricolage Grotesque for headings and prices, Hanken Grotesk for body text; only the 8 type sizes.
> - Stadium buttons, 48 dp targets, one primary action per screen.
> - Every string bilingual through `tr(context, 'English', 'Suomi')`, Finnish first in tone.
> - Real data only; hide empty sections; skeletons that match the layout.
> - Respect reduce motion and 1.3× text.
> - No hard-coded colours or font sizes, no remote fonts or trackers, no dark patterns, no generic green claims.
> - Run `dart run tool/check_tokens.dart --baseline` and `flutter analyze` before finishing.

**References in the repo:** `docs/design-system/README.md` (component API), `docs/design/home-and-drops-redesign.md`, `docs/design/category-sections-v2.md`, `packages/malvoya_ui/example` (the live gallery).
