import '../util.dart';
import 'repository.dart';

/// Datos de ejemplo para probar la app. Supermercados y precios son ficticios
/// (no corresponden a tiendas ni precios reales).
class _P {
  const _P(this.name, this.brand, this.size, this.section, this.price);
  final String name;
  final String brand;
  final String size;
  final String section;
  final double price;
}

const _products = <_P>[
  _P('Plátano de Canarias', '', '1 kg', 'Fruta y verdura', 1.89),
  _P('Tomates', '', '1 kg', 'Fruta y verdura', 2.10),
  _P('Papas', '', '2 kg', 'Fruta y verdura', 2.40),
  _P('Cebollas', '', '1 kg', 'Fruta y verdura', 1.35),
  _P('Pan de barra', '', '250 g', 'Panadería y bollería', 0.65),
  _P('Pechuga de pollo', '', '500 g', 'Carnicería y aves', 4.20),
  _P('Carne picada mixta', '', '400 g', 'Carnicería y aves', 3.60),
  _P('Merluza congelada', '', '400 g', 'Congelados', 4.50),
  _P('Queso tierno de cabra', '', '400 g', 'Charcutería y quesos', 5.40),
  _P('Jamón cocido', '', '200 g', 'Charcutería y quesos', 1.95),
  _P('Leche entera', '', '1 L', 'Lácteos y huevos', 0.95),
  _P('Yogur natural', '', '4 x 125 g', 'Lácteos y huevos', 1.10),
  _P('Huevos', '', '12 ud', 'Lácteos y huevos', 2.65),
  _P('Atún en aceite', '', '3 x 80 g', 'Conservas y salsas', 3.10),
  _P('Tomate frito', '', '400 g', 'Conservas y salsas', 0.99),
  _P('Arroz', '', '1 kg', 'Pasta, arroz y legumbres', 1.25),
  _P('Macarrones', '', '500 g', 'Pasta, arroz y legumbres', 0.85),
  _P('Garbanzos cocidos', '', '400 g', 'Pasta, arroz y legumbres', 0.79),
  _P('Café molido', '', '250 g', 'Desayuno y dulces', 2.95),
  _P('Gofio de millo', '', '1 kg', 'Desayuno y dulces', 2.20),
  _P('Aceite de oliva virgen extra', '', '1 L', 'Aceites, especias y condimentos', 7.90),
  _P('Agua mineral', '', '6 x 1,5 L', 'Bebidas', 2.40),
  _P('Papas fritas', '', '150 g', 'Snacks y aperitivos', 1.45),
  _P('Detergente lavadora', '', '40 lavados', 'Limpieza del hogar', 7.50),
  _P('Papel higiénico', '', '12 rollos', 'Droguería e higiene', 4.30),
  _P('Gel de ducha', '', '750 ml', 'Droguería e higiene', 2.10),
];

class _S {
  const _S(this.name, this.lat, this.lng, this.factor, this.skipEvery);
  final String name;
  final double lat;
  final double lng;
  final double factor; // precio relativo de la tienda
  final int skipEvery; // 0 = todos los precios; n = falta uno de cada n
}

const _stores = <_S>[
  _S('Súper Centro Arrecife (ejemplo)', 28.9630, -13.5500, 1.00, 0),
  _S('Hiper Arrecife Norte (ejemplo)', 28.9800, -13.5300, 0.94, 4),
  _S('Súper Playa Honda (ejemplo)', 28.9480, -13.5880, 1.06, 6),
  _S('Súper Las Palmas GC (ejemplo, otra isla)', 28.1235, -15.4363, 0.85, 0),
];

/// Variación determinista por artículo y tienda (para que no sea un simple %).
double _jitter(int pi, int si) => 1 + (((pi * 7 + si * 13) % 9) - 4) / 100;

Future<void> loadDemoData(Repo repo) async {
  // Tiendas con ubicación
  final storeIds = <String>[];
  for (final s in _stores) {
    final st = await repo.addStore(s.name, chain: 'ejemplo');
    await repo.setStoreLocation(st.id, s.lat, s.lng);
    storeIds.add(st.id);
  }

  // Artículos y precios (hoy y hace unas semanas)
  final productIds = <String>[];
  final today = DateTime.now();
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  for (var pi = 0; pi < _products.length; pi++) {
    final p = _products[pi];
    final prod = await repo.createProduct(
        name: p.name, brand: p.brand, size: p.size, section: p.section);
    productIds.add(prod.id);
    for (var si = 0; si < _stores.length; si++) {
      final s = _stores[si];
      if (s.skipEvery > 0 && pi % s.skipEvery == 0) continue;
      final price = double.parse((p.price * s.factor * _jitter(pi, si)).toStringAsFixed(2));
      // Algunos artículos han bajado de precio y otros han subido.
      final old = double.parse((price * (pi % 5 == 0 ? 1.12 : 0.96)).toStringAsFixed(2));
      await repo.recordPrice(prod.id, storeIds[si], old,
          date: iso(today.subtract(const Duration(days: 21))), notify: false);
      await repo.recordPrice(prod.id, storeIds[si], price,
          offer: (pi + si) % 11 == 0, date: iso(today), notify: false);
    }
  }

  // Compras de las últimas 8 semanas (para habituales, historial y resumen)
  final prices0 = await repo.lastPrices(storeIds.first);
  for (var w = 8; w >= 1; w--) {
    final idx = <int>[0, 4, 10, 12];
    if (w.isEven) idx.addAll([15, 16, 21]);
    if (w % 4 == 0) idx.addAll([19, 23, 24]);
    if (w % 3 == 0) idx.addAll([5, 8]);
    final lines = <({String? productId, String raw, double qty, double? unitPrice, double? amount})>[];
    var total = 0.0;
    for (final i in idx) {
      final pid = productIds[i];
      final unit = prices0[pid] ?? _products[i].price;
      final qty = i == 10 ? 6.0 : (i == 4 ? 2.0 : 1.0);
      total += unit * qty;
      lines.add((productId: pid, raw: _products[i].name, qty: qty, unitPrice: unit, amount: unit * qty));
    }
    await repo.saveTicketPurchase(
      storeId: null,
      storeName: _stores.first.name,
      date: iso(today.subtract(Duration(days: 7 * w))),
      total: double.parse(total.toStringAsFixed(2)),
      lines: lines,
    );
  }

  // Pack de ejemplo
  final pack = await repo.createList('Pack desayuno', isTemplate: true);
  for (final i in const [10, 12, 18, 19]) {
    final prod = await repo.productById(productIds[i]);
    if (prod != null) await repo.addItem(pack.id, prod, notify: false);
  }

  // Lista de ejemplo en la tienda principal
  final list = await repo.createList('Compra semanal (ejemplo)', storeId: storeIds.first);
  const picks = {0: 1.0, 1: 1.0, 4: 2.0, 5: 1.0, 10: 6.0, 12: 1.0, 15: 1.0, 16: 2.0, 19: 1.0, 21: 1.0, 24: 1.0};
  for (final e in picks.entries) {
    final prod = await repo.productById(productIds[e.key]);
    if (prod != null) await repo.addItem(list.id, prod, qty: e.value);
  }
  await repo.createList('Barbacoa sábado (ejemplo)');

  // Zona habitual en Arrecife si no había ninguna (para comparar sin GPS)
  if (await repo.homeZone() == null) {
    await repo.setHomeZone(_stores.first.lat, _stores.first.lng);
  }
  await repo.setSetting('demo_loaded', todayIso());
}
