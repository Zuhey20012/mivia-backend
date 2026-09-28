import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class UploadException implements Exception {
  final String message;
  UploadException(this.message);
  @override
  String toString() => message;
}

/// What Cloudinary returns for a finished upload. The API checks [signature], so the app can
/// never claim an upload that did not happen or that belongs to someone else.
class UploadedMedia {
  final String publicId;
  final Object version;
  final String signature;
  final double? durationSec;

  UploadedMedia({required this.publicId, required this.version, required this.signature, this.durationSec});

  Map<String, dynamic> toProof() => {'publicId': publicId, 'version': version, 'signature': signature};
}

/// Photos and videos go straight from the phone to Cloudinary with a one-time signature from
/// the Malvoya API; the Cloudinary secret never touches the app.
class MediaUpload {
  static const maxVideoBytes = 95 * 1024 * 1024; // single-request upload limit, with margin
  static const maxImageBytes = 15 * 1024 * 1024;

  static Future<UploadedMedia> upload({
    required ApiClient api,
    required String kind, // product_image | store_image | drop_video | drop_image | delivery_proof
    required File file,
    int? orderId,
    void Function(double progress)? onProgress,
  }) async {
    final length = await file.length();
    final isVideo = kind == 'drop_video';
    if (length > (isVideo ? maxVideoBytes : maxImageBytes)) {
      throw UploadException(isVideo
          ? 'This video is too large. Keep it under a minute or record at a lower quality.'
          : 'This photo is too large.');
    }

    final sign = await api.post('/media/sign', {'kind': kind, if (orderId != null) 'orderId': orderId});
    if (!sign.ok) throw UploadException(sign.error!);
    final params = Map<String, dynamic>.from(sign.data['params']);

    final req = http.MultipartRequest('POST', Uri.parse(sign.data['uploadUrl']));
    params.forEach((k, v) => req.fields[k] = '$v');

    var sent = 0;
    final counted = file.openRead().transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        onProgress?.call(sent / length);
        sink.add(chunk);
      },
    ));
    req.files.add(http.MultipartFile('file', counted, length, filename: file.path.split(Platform.pathSeparator).last));

    late http.StreamedResponse res;
    try {
      res = await req.send().timeout(Duration(minutes: isVideo ? 10 : 2));
    } on TimeoutException {
      throw UploadException('The upload took too long. Check your connection and try again.');
    } catch (_) {
      throw UploadException('Upload failed. Check your connection and try again.');
    }
    final body = await res.stream.bytesToString();
    Map<String, dynamic> json = {};
    try {
      json = Map<String, dynamic>.from(jsonDecode(body));
    } catch (_) {}
    if (res.statusCode != 200) {
      final message = json['error']?['message']?.toString();
      throw UploadException(message != null && message.contains('format')
          ? 'This file type is not supported.'
          : 'Upload failed (${res.statusCode}). Please try again.');
    }
    onProgress?.call(1);
    return UploadedMedia(
      publicId: json['public_id'],
      version: json['version'],
      signature: json['signature'],
      durationSec: (json['duration'] as num?)?.toDouble(),
    );
  }

  /// Uploads a product or store photo and returns its URL.
  static Future<String> uploadImage({required ApiClient api, required String kind, required File file, void Function(double)? onProgress}) async {
    final media = await upload(api: api, kind: kind, file: file, onProgress: onProgress);
    final confirm = await api.post('/media/confirm', {'kind': kind, ...media.toProof()});
    if (!confirm.ok) throw UploadException(confirm.error!);
    return confirm.data['media']['url'] as String;
  }
}
