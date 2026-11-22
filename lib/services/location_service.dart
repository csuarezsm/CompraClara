import 'package:geolocator/geolocator.dart';

/// Ubicación del móvil (opcional: si se deniega, la app sigue funcionando).
class LocationService {
  static Future<({double lat, double lng})?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _lastKnown();
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return _lastKnown();
    }
  }

  static Future<({double lat, double lng})?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return null;
    }
  }
}
