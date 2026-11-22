/// Convierte texto libre o dictado en artículos:
/// "2 kg de papas, una docena de huevos y leche x6" ->
/// [papas (2, kg), huevos (12), leche (6)].
class QuickItem {
  QuickItem(this.name, this.qty, this.unit);

  final String name;
  final double qty;

  /// Unidad de medida dicha (kg, g, l…) para anotarla; vacío si son unidades.
  final String unit;

  @override
  String toString() => unit.isEmpty ? '$qty $name' : '$qty $unit $name';
}

const _words = {
  'un': 1.0,
  'uno': 1.0,
  'una': 1.0,
  'dos': 2.0,
  'tres': 3.0,
  'cuatro': 4.0,
  'cinco': 5.0,
  'seis': 6.0,
  'siete': 7.0,
  'ocho': 8.0,
  'nueve': 9.0,
  'diez': 10.0,
  'once': 11.0,
  'doce': 12.0,
  'quince': 15.0,
  'veinte': 20.0,
  'medio': 0.5,
  'media': 0.5,
};

const _units = {
  'kg': 'kg',
  'kilo': 'kg',
  'kilos': 'kg',
  'g': 'g',
  'gr': 'g',
  'gramos': 'g',
  'l': 'l',
  'litro': 'l',
  'litros': 'l',
  'ml': 'ml',
  'paquete': '',
  'paquetes': '',
  'bote': '',
  'botes': '',
  'lata': '',
  'latas': '',
  'botella': '',
  'botellas': '',
  'bolsa': '',
  'bolsas': '',
  'caja': '',
  'cajas': '',
  'unidad': '',
  'unidades': '',
  'ud': '',
  'uds': '',
};

List<QuickItem> parseQuickItems(String text) {
  final parts = text
      .replaceAll('\n', ',')
      .replaceAll(';', ',')
      .split(RegExp(r',|\s+y\s+|\s+e\s+(?=[a-záéíóú])|\s+más\s+', caseSensitive: false))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final out = <QuickItem>[];
  for (final raw in parts) {
    final item = _parseOne(raw);
    if (item != null) out.add(item);
  }
  return out;
}

QuickItem? _parseOne(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  var qty = 1.0;
  var unit = '';

  // "leche x6" / "leche x 6" / "leche (6)"
  final tail = RegExp(r'\s*(?:x|×|\()\s*(\d+(?:[.,]\d+)?)\)?$', caseSensitive: false).firstMatch(s);
  if (tail != null) {
    qty = double.parse(tail.group(1)!.replaceAll(',', '.'));
    s = s.substring(0, tail.start).trim();
  } else {
    final words = s.split(' ');
    var i = 0;
    double? n;
    // "media docena", "una docena"
    if (words.length > 1 && (words[1].toLowerCase() == 'docena' || words[1].toLowerCase() == 'docenas')) {
      final base = double.tryParse(words[0].replaceAll(',', '.')) ?? _words[words[0].toLowerCase()];
      if (base != null) {
        n = base * 12;
        i = 2;
      }
    } else if (words.first.toLowerCase() == 'docena') {
      n = 12;
      i = 1;
    } else {
      n = double.tryParse(words.first.replaceAll(',', '.')) ?? _words[words.first.toLowerCase()];
      if (n != null) i = 1;
    }
    if (n != null && i < words.length) {
      qty = n;
      final u = words[i].toLowerCase().replaceAll('.', '');
      if (_units.containsKey(u) && i + 1 < words.length) {
        unit = _units[u]!;
        i++;
      }
      if (i < words.length && (words[i].toLowerCase() == 'de' || words[i].toLowerCase() == 'del')) i++;
      s = words.sublist(i).join(' ');
    }
  }
  s = s.replaceAll(RegExp(r'^(de|del|el|la|los|las|unos|unas)\s+', caseSensitive: false), '').trim();
  if (s.isEmpty) return null;
  final name = s[0].toUpperCase() + s.substring(1);
  return QuickItem(name, qty <= 0 ? 1 : qty, unit);
}
