import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'api_client.dart';
import 'strings.dart';

/// Google Play's "prominent disclosure" for location (User Data and Location policies).
///
/// The courier must accept it before location sharing starts, and it is shown right before every
/// system location prompt. The app never asks Android for location permission anywhere else
/// (`CourierTelemetryService.start` only checks it). Wording follows docs/play-permissions.md.
class LocationDisclosure {
  LocationDisclosure._();

  static const _key = 'location_disclosure_accepted_v1';

  static AuthService? _auth;

  /// Set once at start-up, so an accepted disclosure is also recorded on the server.
  static void attach(AuthService auth) => _auth = auth;

  /// Records on the server that the courier read the disclosure (`POST /courier/me/disclosures`,
  /// API 2.11: an onboarding step). Idempotent on the server. False when it could not be sent
  /// (signed out, offline, or an older server without the endpoint).
  static Future<bool> report() async {
    final auth = _auth;
    if (auth == null || !auth.isAuthenticated) return false;
    final res = await ApiClient(auth).post('/courier/me/disclosures', {'locationDisclosure': true});
    return res.ok;
  }

  static bool _syncing = false;

  /// Couriers who accepted the disclosure on this phone before the server recorded it: when the
  /// server's [courier] (from `GET /courier/me` or the onboarding checklist) has
  /// `locationDisclosureAt: null` but this phone remembers the acceptance, it is sent once.
  /// Servers without the field are left alone. True when it was recorded now.
  static Future<bool> syncIfMissing(Map? courier) async {
    if (_syncing || courier == null || !courier.containsKey('locationDisclosureAt') || courier['locationDisclosureAt'] != null) return false;
    if (!await isAccepted()) return false;
    _syncing = true;
    try {
      return await report();
    } finally {
      _syncing = false;
    }
  }

  static Future<bool> isAccepted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool isGranted(LocationPermission p) => p == LocationPermission.whileInUse || p == LocationPermission.always;

  /// Shows the disclosure. True when the courier tapped Continue (remembered on this phone and
  /// recorded on the server; [awaitReport] waits for the server, otherwise it is sent alongside).
  static Future<bool> show(BuildContext context, {bool awaitReport = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined, color: AppTheme.primary, size: 32),
        title: Text(tr(ctx, 'Share your location while you are online', 'Sijaintisi jaetaan, kun olet linjoilla')),
        content: SingleChildScrollView(
          child: Text(
            tr(ctx,
                'Malvoya Courier collects your precise location while you are online and during an active delivery, even when the app is closed or not in use, in the background or with the screen off. It is used to offer you delivery jobs near you, check that you are at the store, calculate your pay for the ride to the store, and show your position to the customer so they can follow the delivery.\n\nYour location is shared only with the customer and the store of the order you are delivering. A notification shows the whole time. Sharing stops when you go offline.\n\nMalvoya keeps only your latest position and deletes it when you go offline; the position where you hand over an order is kept with that order for 30 days as proof of delivery. Your location is not used for ads.',
                'Malvoya Courier kerää tarkan sijaintisi, kun olet linjoilla ja kun sinulla on toimitus kesken, myös silloin kun sovellus on suljettu tai ei käytössä, taustalla tai näyttö pois päältä. Sijaintia käytetään lähellä olevien keikkojen tarjoamiseen, sen tarkistamiseen, että olet kaupalla, kauppaan ajon palkkion laskemiseen ja sijaintisi näyttämiseen asiakkaalle, jotta hän voi seurata toimitusta.\n\nSijaintisi jaetaan vain toimittamasi tilauksen asiakkaalle ja kaupalle. Ilmoitus näkyy koko ajan. Jakaminen loppuu, kun poistut linjoilta.\n\nMalvoya säilyttää vain viimeisimmän sijaintisi ja poistaa sen, kun poistut linjoilta; luovutuspaikan sijainti säilytetään tilauksen yhteydessä 30 päivää toimituksen todisteena. Sijaintia ei käytetä mainontaan.'),
            style: const TextStyle(height: 1.45),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Not now', 'Ei nyt'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Continue', 'Jatka'))),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
    // Also on the server; going online does not wait for it
    if (awaitReport) {
      await report();
    } else {
      unawaited(report());
    }
    return true;
  }

  /// Before location sharing starts: the disclosure (when it was never accepted, or whenever the
  /// permission is missing), then, straight after it, Android's permission prompt.
  /// False when the courier chose "Not now". The caller still checks the outcome (the courier may
  /// have refused the system prompt).
  static Future<bool> prepare(BuildContext context) async {
    var permission = await Geolocator.checkPermission();
    if (!await isAccepted() || !isGranted(permission)) {
      if (!context.mounted || !await show(context)) return false;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return true;
  }

  /// True when sharing may restart without asking anything: disclosure accepted and permission held.
  static Future<bool> canResumeSilently() async {
    if (!await isAccepted()) return false;
    try {
      return isGranted(await Geolocator.checkPermission());
    } catch (_) {
      return false;
    }
  }
}
