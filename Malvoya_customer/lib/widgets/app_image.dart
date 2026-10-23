import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../config/theme.dart';

/// Every remote photo in the app: downloaded at the size it is drawn (Cloudinary `w_`, `f_auto`,
/// `q_auto`), decoded at that size (less memory while scrolling), cached on disk, and faded in
/// over a soft pastel placeholder. With "reduce motion" on, photos appear without the fade.
class AppImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;

  /// Pixel width to ask for instead of the laid-out width (e.g. a zoomable full-screen photo).
  final int? requestWidth;

  /// Shown while loading and when the photo is missing or fails. Defaults to a pastel fill.
  final Widget? placeholder;
  final Widget? error;
  final Alignment alignment;

  /// An already-downloaded smaller copy (e.g. the tile photo) shown underneath while this loads.
  final String? previewUrl;

  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.requestWidth,
    this.placeholder,
    this.error,
    this.alignment = Alignment.center,
    this.previewUrl,
  });

  @override
  Widget build(BuildContext context) {
    final pastel = ColoredBox(color: AppTheme.pastel(context, AppTheme.sand, AppTheme.clayInk));
    final soft = placeholder ??
        (previewUrl == null
            ? pastel
            : CachedNetworkImage(imageUrl: previewUrl!, fit: fit, fadeInDuration: Duration.zero, placeholder: (_, __) => pastel, errorWidget: (_, __, ___) => pastel));
    final src = url;
    if (src == null || src.isEmpty) return error ?? soft;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    return LayoutBuilder(builder: (context, box) {
      final px = requestWidth ?? _pixels(box, dpr);
      return CachedNetworkImage(
        imageUrl: sizedImageUrl(src, px),
        fit: fit,
        alignment: alignment,
        width: box.hasBoundedWidth ? box.maxWidth : null,
        height: box.hasBoundedHeight ? box.maxHeight : null,
        // Decoded no larger than needed (the full-size request is left as the server sends it)
        memCacheWidth: requestWidth == null ? px : null,
        fadeInDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => soft,
        errorWidget: (_, __, ___) => error ?? soft,
      );
    });
  }

  /// The width in device pixels; for `cover` the taller side counts too, so a portrait box never
  /// gets a blurry photo.
  int _pixels(BoxConstraints box, double dpr) {
    final w = box.hasBoundedWidth ? box.maxWidth : 600.0;
    final h = box.hasBoundedHeight ? box.maxHeight : 0.0;
    final logical = fit == BoxFit.cover ? math.max(w, h) : w;
    return (logical * dpr).ceil().clamp(64, 2000);
  }
}

/// A cached image provider for avatars and logos ([CircleAvatar.backgroundImage]) of a known size.
ImageProvider sizedImageProvider(BuildContext context, String url, double logicalSize) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  final px = (logicalSize * dpr).ceil();
  return CachedNetworkImageProvider(sizedImageUrl(url, px), maxWidth: px);
}

/// The URL a box of [size] asks for, so a screen can reuse exactly what a tile already downloaded.
String sizedUrlFor(BuildContext context, String url, Size size, {BoxFit fit = BoxFit.cover}) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  final logical = fit == BoxFit.cover ? math.max(size.width, size.height) : size.width;
  return sizedImageUrl(url, (logical * dpr).ceil().clamp(64, 2000));
}

/// A photo flying between a tile and the product page: always the tile's copy (already on the
/// phone), so the flight never waits for, or downloads, other sizes.
HeroFlightShuttleBuilder photoShuttle(String previewUrl) => (context, animation, direction, from, to) => CachedNetworkImage(
      imageUrl: previewUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => ColoredBox(color: AppTheme.pastel(context, AppTheme.sand, AppTheme.clayInk)),
    );
