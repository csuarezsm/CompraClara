import '../data/models.dart';
import '../main.dart' show repo;
import 'location_service.dart';

/// Punto de referencia para comparar: GPS o, si no hay, zona habitual.
class RefPoint {
  RefPoint(this.lat, this.lng, this.fromGps);

  final double lat;
  final double lng;
  final bool fromGps;

  String get label => fromGps ? 'de tu ubicación' : 'de tu zona habitual';
}

Future<RefPoint?> referencePoint({bool useGps = true}) async {
  if (useGps) {
    final p = await LocationService.current();
    if (p != null) return RefPoint(p.lat, p.lng, true);
  }
  final z = await repo.homeZone();
  if (z != null) return RefPoint(z.lat, z.lng, false);
  return null;
}

/// Supermercados dentro del radio configurado (todos si no hay punto de referencia).
Future<List<Store>> nearbyStores({bool useGps = true}) async {
  final ref = await referencePoint(useGps: useGps);
  return repo.storesWithin(ref?.lat, ref?.lng, await repo.radiusKm());
}
