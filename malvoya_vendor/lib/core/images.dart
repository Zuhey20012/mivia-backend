import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// A network picture that is cached on the phone, sized through malvoya_core's [sizedImageUrl], fades in when it
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
    final sized = sizedImageUrlFor(url, width, dpr);
    final image = CachedNetworkImage(
      imageUrl: sized,
      width: width.isFinite ? width : null,
      height: height != null && height!.isFinite ? height : null,
      fit: fit,
      fadeInDuration: MMotion.of(context, MMotion.base),
      memCacheWidth: width.isFinite ? (width * dpr).round() : null,
      placeholder: (_, __) => const MSkeleton(child: MSkeletonBox(height: double.infinity, radius: 0)),
      errorWidget: (context, __, ___) => Container(
        color: context.mColors.primarySoft,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: context.mColors.onPrimarySoft),
      ),
    );
    final child = semanticLabel == null ? image : Semantics(image: true, label: semanticLabel, child: image);
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child) : child;
  }
}

/// [CachedNetworkImageProvider] for a sized Cloudinary copy (e.g. a CircleAvatar's background).
ImageProvider netImageProvider(BuildContext context, String url, {required double size}) =>
    CachedNetworkImageProvider(sizedImageUrlFor(url, size, MediaQuery.maybeDevicePixelRatioOf(context) ?? 2));
