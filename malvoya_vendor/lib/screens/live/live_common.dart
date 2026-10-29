import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// Live shopping (API 2.15): shared bits of the set-up and live screens.
///
/// The store goes live from its phone: `POST /live` creates the live and returns a LiveKit publish
/// token; the video goes to LiveKit over WebRTC and is never recorded.

/// The LiveKit server and the store's publish token from `POST /live` (`publish {url, token}`).
class LivePublish {
  final String url;
  final String token;
  const LivePublish(this.url, this.token);

  /// Reads `publish` (or `watch`) from an answer; null when it is missing or incomplete.
  static LivePublish? from(Object? data) {
    if (data is! Map) return null;
    final p = data['publish'];
    if (p is! Map) return null;
    final url = p['url'];
    final token = p['token'];
    if (url is! String || token is! String || url.isEmpty || token.isEmpty) return null;
    return LivePublish(url, token);
  }
}

/// Maps a map-like JSON value to `Map<String, dynamic>` (null otherwise).
Map<String, dynamic>? asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// The store's live that is still on, from `GET /stores/my/live` (`live` or `current`), or null.
Map<String, dynamic>? currentLiveOf(Map<String, dynamic> data) {
  final live = asMap(data['live']) ?? asMap(data['current']);
  if (live == null || (live['status'] != null && live['status'] != 'LIVE')) return null;
  return live;
}

/// Why a live ended, as the store reads it (`endedReason` / `live:ended {reason}`).
String liveEndedText(BuildContext context, Object? reason) {
  final r = reason?.toString().trim() ?? '';
  return switch (r) {
    '' || 'store' => tr(context, 'You ended the live.', 'Lopetit livelähetyksen.'),
    'timeout' => tr(context, 'The live ended because the app lost its connection for more than 2 minutes.',
        'Livelähetys päättyi, koska sovelluksen yhteys katkesi yli 2 minuutiksi.'),
    'max_duration' => tr(context, 'The live ended after 4 hours, the longest a live can last.',
        'Livelähetys päättyi 4 tunnin jälkeen, mikä on lähetyksen enimmäispituus.'),
    'admin' => tr(context, 'Malvoya ended the live. We emailed you the reason.', 'Malvoya lopetti livelähetyksen. Lähetimme syyn sähköpostiisi.'),
    _ => tr(context, 'Malvoya ended the live: $r', 'Malvoya lopetti livelähetyksen: $r'),
  };
}

/// "12:05" or "1:02:05" for [d].
String elapsedText(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The first photo of a product (`images` holds URLs), or null.
String? productPhoto(Map<String, dynamic> p) {
  final images = p['images'];
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is String) return first;
    if (first is Map && first['url'] is String) return first['url'] as String;
  }
  return null;
}

/// The text of a camera or microphone error: permission refusals get a clear way out.
String mediaErrorText(BuildContext context, Object error, {required bool camera}) {
  final text = error.toString().toLowerCase();
  final denied = text.contains('permission') || text.contains('notallowed') || text.contains('denied') || text.contains('not allowed');
  if (denied) {
    return camera
        ? tr(context, 'Malvoya Store is not allowed to use the camera. Allow the camera for Malvoya Store in your phone\'s settings, then try again.',
            'Malvoya Storella ei ole lupaa käyttää kameraa. Salli kamera Malvoya Storelle puhelimen asetuksista ja yritä uudelleen.')
        : tr(context, 'Malvoya Store is not allowed to use the microphone. Allow the microphone for Malvoya Store in your phone\'s settings, then try again.',
            'Malvoya Storella ei ole lupaa käyttää mikrofonia. Salli mikrofoni Malvoya Storelle puhelimen asetuksista ja yritä uudelleen.');
  }
  return camera
      ? tr(context, 'The camera could not be started. Close other apps that use it and try again.',
          'Kameraa ei voitu käynnistää. Sulje muut kameraa käyttävät sovellukset ja yritä uudelleen.')
      : tr(context, 'The microphone could not be started. Close other apps that use it and try again.',
          'Mikrofonia ei voitu käynnistää. Sulje muut mikrofonia käyttävät sovellukset ja yritä uudelleen.');
}

/// The server's "live is off" answer (503 LIVE_OFF): LiveKit is not configured yet.
bool isLiveOff(ApiResult res) => res.status == 503 && res.data['code'] == 'LIVE_OFF';

String liveOffText(BuildContext context) => tr(context, 'Live video is not switched on yet. Please try again later.',
    'Livevideota ei ole vielä otettu käyttöön. Yritä myöhemmin uudelleen.');

/// Asks before ending a live. True when the store confirmed.
Future<bool> confirmEndLive(BuildContext context, {String? title}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(context, 'End the live?', 'Lopetetaanko livelähetys?')),
      content: Text(title == null || title.isEmpty
          ? tr(context, 'Viewers see that the live has ended. It cannot be continued later.',
              'Katsojat näkevät, että lähetys on päättynyt. Sitä ei voi jatkaa myöhemmin.')
          : tr(context, '"$title" ends for every viewer. It cannot be continued later.',
              '"$title" päättyy kaikilta katsojilta. Sitä ei voi jatkaa myöhemmin.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Stay live', 'Jatka lähetystä'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'End live', 'Lopeta lähetys'))),
      ],
    ),
  );
  return ok == true;
}
