import 'dart:math';

final _rnd = Random();

/// Identificador único (válido también para sincronizar más adelante).
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 31).toRadixString(36)}';

/// 1234.5 -> "1234,50 €"
String money(num? v) {
  if (v == null) return '—';
  return '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// 2.0 -> "2", 1.5 -> "1,5"
String qtyText(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toString().replaceAll('.', ',');
}

double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String todayIso() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String dateEs(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// Distancia en km entre dos puntos (fórmula del haverseno).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

String kmText(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${km.round()} km';
}

/// Lee "28.9636, -13.5477" (formato de Google Maps).
({double lat, double lng})? parseCoords(String text) {
  final nums = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(text)
      .map((m) => double.tryParse(m.group(0)!))
      .whereType<double>()
      .toList();
  if (nums.length < 2) return null;
  final lat = nums[0], lng = nums[1];
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return (lat: lat, lng: lng);
}
