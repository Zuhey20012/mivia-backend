import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// Why the phone's position could not be read.
enum LocateProblem { serviceOff, denied, deniedForever, failed }

/// The phone's position, asked for only when the customer taps "Use my location". It is used to
/// place the map pin and is not sent anywhere until they confirm an address.
class CurrentPosition {
  const CurrentPosition._();

  /// Returns the position, or the reason it could not be read (as the second value).
  static Future<(LatLng?, LocateProblem?)> read() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (null, LocateProblem.serviceOff);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return (null, LocateProblem.deniedForever);
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        return (null, LocateProblem.denied);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      return (LatLng(pos.latitude, pos.longitude), null);
    } catch (_) {
      // Timed out or no fix: the last known position is better than nothing
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return (LatLng(last.latitude, last.longitude), null);
      } catch (_) {}
      return (null, LocateProblem.failed);
    }
  }

  /// A friendly sentence for the customer.
  static String message(BuildContext context, LocateProblem problem) => switch (problem) {
        LocateProblem.serviceOff => tr(context, 'Location is turned off on your phone. Turn it on, or drag the map to your door.',
            'Sijainti on pois päältä puhelimessasi. Laita se päälle tai vedä kartta ovesi kohdalle.'),
        LocateProblem.denied => tr(context, 'No problem: drag the map to your door, or search for your street.',
            'Ei haittaa: vedä kartta ovesi kohdalle tai hae katuosoitteella.'),
        LocateProblem.deniedForever => tr(context, 'Location access is off for Malvoya. You can allow it in your phone’s settings, or drag the map to your door.',
            'Malvoyalla ei ole lupaa sijaintiin. Voit sallia sen puhelimen asetuksista tai vetää kartan ovesi kohdalle.'),
        LocateProblem.failed => tr(context, 'Your location could not be found right now. Drag the map to your door instead.',
            'Sijaintiasi ei juuri nyt löytynyt. Vedä kartta ovesi kohdalle.'),
      };

  /// Opens the phone's settings for this app (after "don't ask again") or for location services.
  static Future<void> openSettings(LocateProblem problem) async {
    try {
      if (problem == LocateProblem.serviceOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
}
