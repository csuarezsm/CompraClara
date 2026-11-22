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

String isoDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Lee el formato de un artículo y lo pasa a unidad base:
/// "1 L" -> 1 l, "500 g" -> 0,5 kg, "6 x 1,5 L" -> 9 l, "12 ud" -> 12 ud, "750 ml" -> 0,75 l.
({double qty, String unit})? parseSize(String size) {
  final s = size.toLowerCase().replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'(?:(\d+(?:\.\d+)?)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|kilo|kilos|g|gr|grs|gramos|l|lt|litro|litros|cl|ml|ud|uds|u|unidades|unidad|rollos|lavados|bolsitas|cápsulas|capsulas)\b')
      .firstMatch(s);
  if (m == null) return null;
  final mult = m.group(1) == null ? 1.0 : double.parse(m.group(1)!);
  final n = double.parse(m.group(2)!);
  final u = m.group(3)!;
  double qty;
  String unit;
  switch (u) {
    case 'kg':
    case 'kilo':
    case 'kilos':
      qty = n;
      unit = 'kg';
    case 'g':
    case 'gr':
    case 'grs':
    case 'gramos':
      qty = n / 1000;
      unit = 'kg';
    case 'l':
    case 'lt':
    case 'litro':
    case 'litros':
      qty = n;
      unit = 'l';
    case 'cl':
      qty = n / 100;
      unit = 'l';
    case 'ml':
      qty = n / 1000;
      unit = 'l';
    default:
      qty = n;
      unit = 'ud';
  }
  final total = qty * mult;
  if (total <= 0) return null;
  return (qty: total, unit: unit);
}

/// "12,34 €/kg"
String unitPriceText(double value, String unit) => '${money(value)}/$unit';

/// Texto de ticket normalizado para reconocer alias ("LECHE  ENT. 1L" -> "leche ent 1l").
String normalizeTicketText(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String csvCell(Object? v) {
  final s = (v ?? '').toString();
  if (s.contains(';') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvNum(Object? v) {
  if (v == null) return '';
  if (v is num) return v.toStringAsFixed(2).replaceAll('.', ',');
  return v.toString();
}
