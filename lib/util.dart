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
