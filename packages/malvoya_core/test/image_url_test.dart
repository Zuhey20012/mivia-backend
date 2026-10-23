import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_core/malvoya_core.dart';

const base = 'https://res.cloudinary.com/malvoya/image/upload';

void main() {
  test('adds a delivery transformation to a plain upload URL', () {
    expect(sizedImageUrl('$base/v171/products/s1/a.jpg', 300), '$base/c_limit,w_320,q_auto,f_auto/v171/products/s1/a.jpg');
  });

  test('rewrites the standard transformation to the drawn width', () {
    expect(sizedImageUrl('$base/c_limit,w_1200,q_auto,f_auto/v1/p.jpg', 500), '$base/c_limit,q_auto,f_auto,w_640/v1/p.jpg');
  });

  test('never asks for more than the server sent', () {
    expect(sizedImageUrl('$base/c_limit,w_400,q_auto,f_auto/v1/p.jpg', 1900), '$base/c_limit,q_auto,f_auto,w_400/v1/p.jpg');
  });

  test('video posters keep their jpg format', () {
    const poster = 'https://res.cloudinary.com/malvoya/video/upload/so_0,c_limit,w_720,q_auto,f_jpg/v1/d.jpg';
    expect(sizedImageUrl(poster, 200), 'https://res.cloudinary.com/malvoya/video/upload/so_0,c_limit,q_auto,f_jpg,w_240/v1/d.jpg');
  });

  test('other hosts, crops and overlays are left alone', () {
    expect(sizedImageUrl('https://example.com/a.jpg', 300), 'https://example.com/a.jpg');
    const overlay = '$base/l_logo,g_south/v1/p.jpg';
    expect(sizedImageUrl(overlay, 300), overlay);
    const video = 'https://res.cloudinary.com/malvoya/video/upload/v1/d.m3u8';
    expect(sizedImageUrl(video, 300), video);
    expect(sizedImageUrl('$base/v1/p.jpg', 0), '$base/v1/p.jpg');
  });

  test('widths snap to shared steps', () {
    expect(imageWidthBucket(1), 160);
    expect(imageWidthBucket(161), 240);
    expect(imageWidthBucket(5000), 2000);
    expect(sizedImageUrlFor('$base/v1/p.jpg', 100, 3), '$base/c_limit,w_320,q_auto,f_auto/v1/p.jpg');
  });
}
