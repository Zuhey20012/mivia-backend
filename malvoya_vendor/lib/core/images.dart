import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../widgets/loading_states.dart';

/// Asks Cloudinary for a copy sized for where the picture is shown, instead of the full upload.
///
/// Only public `…/image/upload/…` URLs are changed. Signed or private URLs (delivery proofs), URLs
/// that already carry a transformation and anything not on Cloudinary are returned unchanged.
/// Sizes are rounded up to steps of 100 px so nearby sizes share one cached copy.
String cloudinarySized(String url, {required double width, double? height, double dpr = 2}) {
  const marker = '/image/upload/';
  final at = url.indexOf(marker);
  if (at < 0 || !url.contains('res.cloudinary.com')) return url;
  final rest = url.substring(at + marker.length);
  // "v1712345/…" (a version) or a folder: no transformation yet. Anything else (e.g. "c_fill,…") has one.
  final first = rest.split('/').first;
  if (RegExp(r'^[a-z]{1,3}_').hasMatch(first)) return url;
  int px(double logical) => (((logical * dpr) / 100).ceil() * 100).clamp(100, 2000);
  final parts = ['c_fill', 'w_${px(width)}', if (height != null) 'h_${px(height)}', 'q_auto'];
  return '${url.substring(0, at + marker.length)}${parts.join(',')}/$rest';
}

/// A network picture that is cached on the phone, sized through [cloudinarySized], fades in when it
/// arrives and shows a soft placeholder meanwhile. Use it for every product, store and drop picture.
class NetImage extends StatelessWidget {
  final String url;
  final double width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final String? semanticLabel;
  const NetImage(this.url, {super.key, required this.width, this.height, this.fit = BoxFit.cover, this.radius = 0, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final sized = cloudinarySized(url, width: width, height: height, dpr: dpr);
    final image = CachedNetworkImage(
      imageUrl: sized,
      width: width.isFinite ? width : null,
      height: height != null && height!.isFinite ? height : null,
      fit: fit,
      fadeInDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 220),
      memCacheWidth: width.isFinite ? (width * dpr).round() : null,
      placeholder: (_, __) => const Shimmering(child: SkeletonBox(height: double.infinity, radius: 0)),
      errorWidget: (_, __, ___) => Container(
        color: AppTheme.primaryLight,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: AppTheme.primary),
      ),
    );
    final child = semanticLabel == null ? image : Semantics(image: true, label: semanticLabel, child: image);
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child) : child;
  }
}

/// [CachedNetworkImageProvider] for a sized Cloudinary copy (e.g. a CircleAvatar's background).
ImageProvider netImageProvider(BuildContext context, String url, {required double size}) =>
    CachedNetworkImageProvider(cloudinarySized(url, width: size, height: size, dpr: MediaQuery.maybeDevicePixelRatioOf(context) ?? 2));
