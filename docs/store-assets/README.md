# Store assets

| Path | What |
|---|---|
| `<app>/play-icon-512.png` | Google Play icon, 512 × 512 (`customer`, `store`, `courier`) |
| `<app>/app-store-icon-1024.png` | App Store icon, 1024 × 1024, no alpha (same as in the Xcode asset catalog) |
| `<app>/feature-graphic-en.png`, `-fi.png` | Google Play feature graphic, 1024 × 500, no alpha |
| `<app>/source/` | SVG sources, iOS 18 dark and tinted icon variants (optional, not wired into Xcode) |
| `<app>/source/generator/` | Inputs for `flutter_launcher_icons` / `flutter_native_splash` (see below) |
| `feature-graphic.html` | Template for the feature graphic (can show a real screenshot later) |
| `screenshot-kit/` | Frames real screenshots for Play and the App Store; `README.md` explains how to take them |
| `promo-video-plan.md` | Storyboards for the Play and App Store videos |
| `shared/` | Brand fonts (embedded, OFL licences) and the mark/caption data used by the pages |

## The icon family

The "Thread M" from `lib/widgets/brand_mark.dart` on each app's brand colour (Malva `#6D2E8C`, Moss `#2E6B4F`, Lingon `#C2412D`), drawn in Birch. The thread ends in a sunshine `#F2C14E` accent whose **shape** tells the apps apart even without colour (Android 13 themed icons, colour blindness):

- **Malvoya**: a round dot (the map pin: you, here),
- **Malvoya Store**: a rounded square (the shop),
- **Malvoya Courier**: a navigation arrow (on the way).

The in-app `BrandMark` widget still ends in a Birch dot; that is fine (it is the logo, the icons are the app markers).

## Regenerating launcher icons or splash

The native icons and splash in `android/app/src/main/res` and `ios/Runner` were written directly (adaptive icon with a **monochrome** layer, splash without a white flash). `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` would overwrite them with the old art from `assets/brand/` and drop the monochrome layer and the window-colour fixes. If you want to use the generators again, first copy `source/generator/*` to the app's `assets/brand/` and add to `flutter_launcher_icons.yaml`:

```yaml
  adaptive_icon_monochrome: "assets/brand/icon_mono.png"
```

and in `flutter_native_splash.yaml` set `android_12: image: assets/brand/splash_android12.png`. Then check `values*/styles.xml` again: the generator removes `@color/window_background` from `NormalTheme`.
