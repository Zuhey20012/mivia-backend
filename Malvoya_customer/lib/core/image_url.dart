/// Asks Cloudinary for an image no larger than it is drawn, in the best format for the phone
/// (`f_auto`, `q_auto`, `w_<px>`). Other hosts are returned unchanged.
///
/// The API sends images with a standard delivery transformation (`c_limit,w_1200,q_auto,f_auto`)
/// and video posters with `so_0,c_limit,w_720,q_auto,f_jpg`. Those are rewritten to the width the
/// widget needs; any other transformation (crops, overlays, signed URLs) is left as it is.
String sizedImageUrl(String url, int widthPx) {
  if (widthPx <= 0 || !url.startsWith('https://res.cloudinary.com/')) return url;
  final String kind;
  if (url.contains('/image/upload/')) {
    kind = 'image';
  } else if (url.contains('/video/upload/')) {
    kind = 'video';
  } else {
    return url;
  }
  final marker = '/$kind/upload/';
  final start = url.indexOf(marker) + marker.length;
  final end = url.indexOf('/', start);
  if (end < 0) return url; // no public ID after the segment
  final next = url.substring(start, end);
  final target = _bucket(widthPx);

  if (!_isTransformation(next)) {
    // Plain upload URL: only images get a delivery transformation added
    if (kind != 'image') return url;
    return '${url.substring(0, start)}c_limit,w_$target,q_auto,f_auto/${url.substring(start)}';
  }
  final params = next.split(',');
  const allowed = {'c', 'w', 'h', 'q', 'f', 'so', 'dpr'};
  if (!params.every((p) => allowed.contains(p.split('_').first))) return url;
  int? existingW;
  for (final p in params) {
    if (p.startsWith('w_')) existingW = int.tryParse(p.substring(2));
  }
  // Never more than the server's own limit (the largest size worth sending)
  final w = existingW != null && existingW < target ? existingW : target;
  final out = <String>[
    for (final p in params)
      if (!p.startsWith('w_')) p,
  ];
  if (!out.any((p) => p.startsWith('c_'))) out.insert(0, 'c_limit');
  out.add('w_$w');
  if (!out.any((p) => p.startsWith('q_'))) out.add('q_auto');
  if (kind == 'image' && !out.any((p) => p.startsWith('f_'))) out.add('f_auto');
  return '${url.substring(0, start)}${out.join(',')}${url.substring(end)}';
}

/// A version segment (`v1712345678`) or a folder name is not a transformation.
bool _isTransformation(String segment) =>
    !RegExp(r'^v\d+$').hasMatch(segment) && RegExp(r'^[a-z]{1,4}_[a-z0-9_.:,]+$').hasMatch(segment) && segment.contains(RegExp(r'(^|,)[a-z]{1,4}_'));

/// A few fixed widths, so the same photo drawn at slightly different sizes is downloaded once.
int _bucket(int px) {
  const steps = [160, 240, 320, 400, 480, 640, 800, 960, 1200, 1600, 2000];
  for (final s in steps) {
    if (px <= s) return s;
  }
  return steps.last;
}
