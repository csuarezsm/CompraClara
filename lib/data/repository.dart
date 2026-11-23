import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../util.dart';
import 'database.dart';
import 'models.dart';
import 'sections.dart';

/// Acceso a datos. Cada cambio avisa a las pantallas (ChangeNotifier).
class Repo extends ChangeNotifier {
  Repo._(this.db);

  final Database db;

  static Future<Repo> open() async => Repo._(await AppDb.open());

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _changed() => notifyListeners();

  /// Avisa a las pantallas tras cambios hechos en bloque.
  void refresh() => _changed();

  // ---------------------------------------------------------------- Tiendas

  Future<List<Store>> stores() async {
    final r = await db.query('stores', orderBy: 'name COLLATE NOCASE');
    return r.map(Store.fromMap).toList();
  }

  Future<Store?> storeById(String? id) async {
    if (id == null) return null;
    final r = await db.query('stores', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Store.fromMap(r.first);
  }

  Future<Store?> storeByGlobalId(String globalId) async {
    final r = await db.query('stores', where: 'global_id = ?', whereArgs: [globalId], limit: 1);
    return r.isEmpty ? null : Store.fromMap(r.first);
  }

  /// Enlaza una tienda local con el catálogo común.
  Future<void> linkStore(String id,
      {required String globalId, required String chainKey, String address = '', double? lat, double? lng}) async {
    await db.update(
        'stores',
        {
          'global_id': globalId,
          'chain_key': chainKey,
          'address': address,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
        },
        where: 'id = ?',
        whereArgs: [id]);
    _changed();
  }

  /// Une dos tiendas locales que son la misma: precios, listas, compras y
  /// recorrido pasan a [toId] y [fromId] se borra.
  Future<void> mergeLocalStores(String fromId, String toId) async {
    if (fromId == toId) return;
    await db.transaction((t) async {
      await t.update('prices', {'store_id': toId}, where: 'store_id = ?', whereArgs: [fromId]);
      await t.update('lists', {'store_id': toId}, where: 'store_id = ?', whereArgs: [fromId]);
      await t.update('purchases', {'store_id': toId}, where: 'store_id = ?', whereArgs: [fromId]);
      await t.delete('product_store', where: 'store_id = ?', whereArgs: [fromId]);
      await t.delete('route_log', where: 'store_id = ?', whereArgs: [fromId]);
      await t.delete('stores', where: 'id = ?', whereArgs: [fromId]);
    });
    _changed();
  }

  /// Crea la tienda con la plantilla de secciones.
  Future<Store> addStore(String name,
      {String chain = '',
      String? globalId,
      String chainKey = '',
      String address = '',
      double? lat,
      double? lng}) async {
    final id = newId();
    await db.transaction((t) async {
      await t.insert('stores', {
        'id': id,
        'name': name,
        'chain': chain,
        'global_id': globalId,
        'chain_key': chainKey,
        'address': address,
        'lat': lat,
        'lng': lng,
        'created_at': _now,
      });
      var i = 0;
      for (final s in defaultSections) {
        await t.insert('store_sections', {
          'id': newId(),
          'store_id': id,
          'name': s,
          'position': i++,
          'hidden': 0,
        });
      }
    });
    _changed();
    return Store(
        id: id,
        name: name,
        chain: chain,
        globalId: globalId,
        chainKey: chainKey,
        address: address,
        lat: lat,
        lng: lng);
  }

  Future<void> renameStore(String id, String name) async {
    await db.update('stores', {'name': name}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setStoreLocation(String id, double? lat, double? lng) async {
    await db.update('stores', {'lat': lat, 'lng': lng}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteStore(String id) async {
    await db.delete('stores', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Tienda con ubicación más cercana a un punto, si está a menos de [maxKm].
  Future<({Store store, double km})?> nearestStore(double lat, double lng,
      {double maxKm = 0.3}) async {
    ({Store store, double km})? best;
    for (final s in await stores()) {
      if (!s.hasLocation) continue;
      final d = distanceKm(lat, lng, s.lat!, s.lng!);
      if (d <= maxKm && (best == null || d < best.km)) best = (store: s, km: d);
    }
    return best;
  }

  /// Tiendas dentro del radio de un punto (todas si no hay punto).
  Future<List<Store>> storesWithin(double? lat, double? lng, double radiusKm) async {
    final all = await stores();
    if (lat == null || lng == null) return all;
    return all
        .where((s) => s.hasLocation && distanceKm(lat, lng, s.lat!, s.lng!) <= radiusKm)
        .toList();
  }

  // ----------------------------------------------------------------- Ajustes

  Future<String?> getSetting(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    _changed();
  }

  /// Distancia máxima (km) para comparar supermercados. Por defecto 20 km.
  Future<double> radiusKm() async => double.tryParse(await getSetting('radius_km') ?? '') ?? 20;

  Future<void> setRadiusKm(double km) => setSetting('radius_km', km.toStringAsFixed(0));

  /// Zona habitual: punto de referencia si no hay GPS.
  Future<({double lat, double lng})?> homeZone() async {
    final lat = double.tryParse(await getSetting('zone_lat') ?? '');
    final lng = double.tryParse(await getSetting('zone_lng') ?? '');
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  Future<void> setHomeZone(double? lat, double? lng) async {
    await setSetting('zone_lat', lat?.toString());
    await setSetting('zone_lng', lng?.toString());
  }

  /// Presupuesto mensual de compra (null = sin presupuesto).
  Future<double?> monthlyBudget() async => double.tryParse(await getSetting('monthly_budget') ?? '');

  Future<void> setMonthlyBudget(double? v) =>
      setSetting('monthly_budget', v?.toStringAsFixed(2));

  /// Alérgenos a evitar (claves de Open Food Facts: gluten, milk, eggs…).
  Future<Set<String>> avoidAllergens() async {
    final v = await getSetting('avoid_allergens') ?? '';
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> setAvoidAllergens(Set<String> v) => setSetting('avoid_allergens', v.join(','));

  /// Dietas (vegan, vegetarian, gluten-free…) para avisar en artículos.
  Future<Set<String>> diets() async {
    final v = await getSetting('diets') ?? '';
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> setDiets(Set<String> v) => setSetting('diets', v.join(','));

  /// Borra todos los datos del móvil.
  Future<void> clearAll() async {
    await db.transaction((t) async {
      for (final table in allTables.reversed) {
        await t.delete(table);
      }
    });
    _changed();
  }

  /// Orden de tablas respetando dependencias (para copias de seguridad).
  static const allTables = [
    'settings',
    'stores',
    'store_sections',
    'products',
    'barcodes',
    'product_store',
    'lists',
    'list_items',
    'prices',
    'purchases',
    'purchase_items',
    'aliases',
    'route_log',
    'cards',
    'coupons',
  ];

  // ------------------------------------------------------ Secciones de tienda

  Future<List<StoreSection>> sections(String storeId) async {
    final r = await db.query(
      'store_sections',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'position ASC',
    );
    return r.map(StoreSection.fromMap).toList();
  }

  Future<void> addSection(String storeId, String name) async {
    final r = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS m FROM store_sections WHERE store_id = ?',
      [storeId],
    );
    final next = ((r.first['m'] as int?) ?? -1) + 1;
    await db.insert('store_sections', {
      'id': newId(),
      'store_id': storeId,
      'name': name,
      'position': next,
      'hidden': 0,
    });
    _changed();
  }

  Future<void> renameSection(String id, String name) async {
    await db.update('store_sections', {'name': name}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setSectionHidden(String id, bool hidden) async {
    await db.update('store_sections', {'hidden': hidden ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteSection(String id) async {
    await db.delete('store_sections', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> reorderSections(List<String> orderedIds) async {
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('store_sections', {'position': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
    _changed();
  }

  /// Añade las secciones de la plantilla que falten. Devuelve cuántas añadió.
  Future<int> applyTemplate(String storeId) async {
    final existing = (await sections(storeId)).map((s) => s.name.toLowerCase()).toSet();
    var added = 0;
    for (final name in defaultSections) {
      if (!existing.contains(name.toLowerCase())) {
        await addSection(storeId, name);
        added++;
      }
    }
    return added;
  }

  /// Número de compras registradas en la tienda con orden de recorrido.
  Future<int> routeSamples(String storeId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(DISTINCT date) AS n FROM route_log WHERE store_id = ?', [storeId]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// Ordena las secciones según el orden real en que se cogen las cosas.
  /// Las secciones sin datos mantienen su posición relativa.
  Future<bool> applyLearnedOrder(String storeId) async {
    final secs = await sections(storeId);
    if (secs.length < 2) return false;
    final r = await db.rawQuery(
      'SELECT section_id, AVG(rank) AS r FROM route_log WHERE store_id = ? GROUP BY section_id',
      [storeId],
    );
    if (r.isEmpty) return false;
    final learned = {for (final m in r) m['section_id'] as String: (m['r'] as num).toDouble()};
    final n = secs.length - 1;
    final scored = <(String, double)>[];
    for (var i = 0; i < secs.length; i++) {
      final s = secs[i];
      scored.add((s.id, learned[s.id] ?? (i / n)));
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    await reorderSections(scored.map((e) => e.$1).toList());
    return true;
  }

  // -------------------------------------------------------------- Artículos

  Future<List<Product>> products({String query = ''}) async {
    final q = query.trim();
    final List<Map<String, Object?>> r;
    if (q.isEmpty) {
      r = await db.query('products', orderBy: 'name COLLATE NOCASE');
    } else {
      r = await db.query(
        'products',
        where: 'name LIKE ? OR brand LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'name COLLATE NOCASE',
      );
    }
    return r.map(Product.fromMap).toList();
  }

  Future<Product?> productById(String id) async {
    final r = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  /// Busca un artículo por nombre exacto (sin distinguir mayúsculas).
  /// Artículo con el mismo nombre, sin distinguir mayúsculas, acentos ni signos.
  Future<Product?> productByName(String name) async {
    final n = normText(name);
    if (n.isEmpty) return null;
    for (final p in await products()) {
      if (normText(p.name) == n) return p;
    }
    return null;
  }

  /// Artículos que pueden ser el mismo: nombre igual, o uno contiene al otro
  /// (p. ej. «Leche» y «Leche entera»). Los iguales primero; como mucho 6.
  Future<List<Product>> similarProducts(String name, {String? exceptId}) async {
    final n = normText(name);
    if (n.length < 3) return [];
    final exact = <Product>[];
    final close = <Product>[];
    for (final p in await products()) {
      if (p.id == exceptId) continue;
      final pn = normText(p.name);
      if (pn == n) {
        exact.add(p);
      } else if ((pn.contains(n) || n.contains(pn)) && pn.length >= 3) {
        close.add(p);
      }
    }
    return [...exact, ...close].take(6).toList();
  }

  Future<Product> createProduct({
    required String name,
    String brand = '',
    String size = '',
    String? section,
    String notes = '',
    String allergens = '',
    String nutriscore = '',
    String labels = '',
  }) async {
    final unit = parseSize(size);
    final p = Product(
      id: newId(),
      name: cleanName(name),
      brand: brand.trim(),
      size: size.trim(),
      section: section ?? guessSection(name),
      notes: notes.trim(),
      unitQty: unit?.qty,
      unit: unit?.unit,
      allergens: allergens,
      nutriscore: nutriscore,
      labels: labels,
    );
    await db.insert('products', {
      'id': p.id,
      'name': p.name,
      'brand': p.brand,
      'size': p.size,
      'section': p.section,
      'notes': p.notes,
      'unit_qty': p.unitQty,
      'unit': p.unit,
      'allergens': p.allergens,
      'nutriscore': p.nutriscore,
      'labels': p.labels,
      'created_at': _now,
    });
    _changed();
    return p;
  }

  Future<void> updateProduct(Product p) async {
    final unit = parseSize(p.size);
    await db.update(
      'products',
      {
        'name': cleanName(p.name),
        'brand': p.brand.trim(),
        'size': p.size.trim(),
        'section': p.section,
        'notes': p.notes.trim(),
        'unit_qty': unit?.qty,
        'unit': unit?.unit,
        'allergens': p.allergens,
        'nutriscore': p.nutriscore,
        'labels': p.labels,
      },
      where: 'id = ?',
      whereArgs: [p.id],
    );
    _changed();
  }

  Future<void> setProductFoodInfo(String id,
      {required String allergens, required String nutriscore, required String labels}) async {
    await db.update(
        'products', {'allergens': allergens, 'nutriscore': nutriscore, 'labels': labels},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteProduct(String id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<Product?> productByBarcode(String ean) async {
    final r = await db.rawQuery(
      'SELECT p.* FROM products p JOIN barcodes b ON b.product_id = p.id WHERE b.ean = ?',
      [ean],
    );
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  Future<List<String>> barcodesOf(String productId) async {
    final r = await db.query('barcodes', where: 'product_id = ?', whereArgs: [productId]);
    return r.map((m) => m['ean'] as String).toList();
  }

  /// false si el código ya pertenece a otro artículo.
  Future<bool> addBarcode(String productId, String ean) async {
    final owner = await db.query('barcodes', where: 'ean = ?', whereArgs: [ean]);
    if (owner.isNotEmpty) {
      return owner.first['product_id'] == productId;
    }
    await db.insert('barcodes', {'ean': ean, 'product_id': productId});
    _changed();
    return true;
  }

  Future<void> removeBarcode(String ean) async {
    await db.delete('barcodes', where: 'ean = ?', whereArgs: [ean]);
    _changed();
  }

  /// storeId -> sectionId (ubicación concreta del artículo en cada tienda).
  Future<Map<String, String>> locationsOf(String productId) async {
    final r = await db.query('product_store', where: 'product_id = ?', whereArgs: [productId]);
    return {for (final m in r) m['store_id'] as String: m['section_id'] as String};
  }

  Future<Map<String, String>> locationsInStore(String storeId) async {
    final r = await db.query('product_store', where: 'store_id = ?', whereArgs: [storeId]);
    return {for (final m in r) m['product_id'] as String: m['section_id'] as String};
  }

  Future<void> setLocation(String productId, String storeId, String? sectionId) async {
    if (sectionId == null) {
      await db.delete('product_store',
          where: 'product_id = ? AND store_id = ?', whereArgs: [productId, storeId]);
    } else {
      await db.insert(
        'product_store',
        {'product_id': productId, 'store_id': storeId, 'section_id': sectionId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _changed();
  }

  /// Sección de una tienda donde está un artículo:
  /// 1) ubicación concreta, 2) misma sección por nombre, 3) «Otros».
  static StoreSection? resolveSection(
    String productSection,
    String productId,
    List<StoreSection> sections,
    Map<String, String> overrides,
  ) {
    final ov = overrides[productId];
    if (ov != null) {
      for (final s in sections) {
        if (s.id == ov) return s;
      }
    }
    final byName = productSection.toLowerCase();
    for (final s in sections) {
      if (s.name.toLowerCase() == byName) return s;
    }
    for (final s in sections) {
      if (s.name.toLowerCase() == otherSection.toLowerCase()) return s;
    }
    return null;
  }

  // ----------------------------------------------------------------- Listas

  static const _listSelect = '''
      SELECT l.*,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id) AS total,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id AND i.status = 1) AS picked
      FROM lists l''';

  Future<List<ShoppingList>> lists({bool archived = false, bool templates = false}) async {
    final r = await db.rawQuery(
      '$_listSelect WHERE l.archived = ? AND l.is_template = ? ORDER BY l.created_at DESC',
      [archived ? 1 : 0, templates ? 1 : 0],
    );
    return r.map(ShoppingList.fromMap).toList();
  }

  Future<ShoppingList?> listById(String id) async {
    final r = await db.rawQuery('$_listSelect WHERE l.id = ?', [id]);
    return r.isEmpty ? null : ShoppingList.fromMap(r.first);
  }

  Future<ShoppingList> createList(String name, {String? storeId, bool isTemplate = false}) async {
    final id = newId();
    await db.insert('lists', {
      'id': id,
      'name': name,
      'store_id': storeId,
      'archived': 0,
      'is_template': isTemplate ? 1 : 0,
      'created_at': _now,
    });
    _changed();
    return ShoppingList(id: id, name: name, storeId: storeId, isTemplate: isTemplate);
  }

  Future<void> renameList(String id, String name) async {
    await db.update('lists', {'name': name}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setListStore(String id, String? storeId) async {
    await db.update('lists', {'store_id': storeId}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setListBudget(String id, double? budget) async {
    await db.update('lists', {'budget': budget}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setListArchived(String id, bool archived) async {
    await db.update('lists', {'archived': archived ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteList(String id) async {
    await db.delete('lists', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Deja todos los artículos de la lista como pendientes (reutilizar lista).
  Future<void> uncheckAll(String listId) async {
    await db.update(
        'list_items', {'status': statusPending, 'price': null, 'picked_qty': null, 'picked_at': null},
        where: 'list_id = ?', whereArgs: [listId]);
    _changed();
  }

  /// Copia una lista (o la convierte en plantilla/pack). Todo queda pendiente.
  Future<String> duplicateList(String id, {required String name, bool asTemplate = false}) async {
    final src = await listById(id);
    final newL = await createList(name, storeId: src?.storeId, isTemplate: asTemplate);
    final its = await items(id);
    var pos = 0;
    final batch = db.batch();
    for (final it in its) {
      batch.insert('list_items', {
        'id': newId(),
        'list_id': newL.id,
        'product_id': it.productId,
        'qty': it.qty,
        'note': it.note,
        'status': statusPending,
        'position': pos++,
      });
    }
    await batch.commit(noResult: true);
    _changed();
    return newL.id;
  }

  /// Añade todos los artículos de un pack/plantilla a una lista. Devuelve cuántos.
  Future<int> addPackToList(String packId, String listId) async {
    var n = 0;
    for (final it in await items(packId)) {
      final p = await productById(it.productId);
      if (p == null) continue;
      await addItem(listId, p, qty: it.qty, notify: false);
      n++;
    }
    _changed();
    return n;
  }

  // ------------------------------------------------------ Líneas de la lista

  Future<List<ListItem>> items(String listId) async {
    final r = await db.rawQuery('''
      SELECT i.*, p.name AS pname, p.brand AS pbrand, p.size AS psize, p.section AS psection,
             p.allergens AS pallergens, p.labels AS plabels
      FROM list_items i LEFT JOIN products p ON p.id = i.product_id
      WHERE i.list_id = ?
      ORDER BY i.position ASC
    ''', [listId]);
    return r.map(ListItem.fromMap).toList();
  }

  /// Añade un artículo. Si ya está pendiente en la lista, suma la cantidad
  /// y devuelve true (nunca se duplica).
  Future<bool> addItem(String listId, Product product,
      {double qty = 1, String note = '', bool notify = true}) async {
    final existing = await db.query(
      'list_items',
      where: 'list_id = ? AND product_id = ? AND status = ?',
      whereArgs: [listId, product.id, statusPending],
    );
    if (existing.isNotEmpty) {
      final cur = (existing.first['qty'] as num).toDouble();
      await db.update('list_items', {'qty': cur + qty},
          where: 'id = ?', whereArgs: [existing.first['id']]);
      if (notify) _changed();
      return true;
    }
    final m = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS m FROM list_items WHERE list_id = ?',
      [listId],
    );
    final pos = ((m.first['m'] as int?) ?? -1) + 1;
    await db.insert('list_items', {
      'id': newId(),
      'list_id': listId,
      'product_id': product.id,
      'qty': qty,
      'note': note,
      'status': statusPending,
      'position': pos,
    });
    if (notify) _changed();
    return false;
  }

  Future<void> restoreItem(ListItem item) async {
    await db.insert('list_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  Future<void> setQty(String itemId, double qty) async {
    await db.update('list_items', {'qty': qty < 0.01 ? 0.01 : qty},
        where: 'id = ?', whereArgs: [itemId]);
    _changed();
  }

  Future<void> setNote(String itemId, String note) async {
    await db.update('list_items', {'note': note}, where: 'id = ?', whereArgs: [itemId]);
    _changed();
  }

  Future<void> setStatus(String itemId, int status) async {
    await db.update(
      'list_items',
      {
        'status': status,
        'picked_at': status == statusPicked ? _now : null,
        if (status != statusPicked) 'picked_qty': null,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
    _changed();
  }

  /// Coge solo parte de la cantidad: lo cogido queda marcado y el resto
  /// sigue pendiente en una línea nueva.
  Future<void> pickPartial(ListItem item, double picked) async {
    if (picked <= 0) return;
    if (picked >= item.qty) {
      await setStatus(item.id, statusPicked);
      return;
    }
    await db.transaction((t) async {
      await t.update('list_items',
          {'status': statusPicked, 'picked_qty': picked, 'picked_at': _now},
          where: 'id = ?', whereArgs: [item.id]);
      await t.insert('list_items', {
        'id': newId(),
        'list_id': item.listId,
        'product_id': item.productId,
        'qty': item.qty - picked,
        'note': item.note,
        'status': statusPending,
        'position': item.position,
      });
    });
    _changed();
  }

  /// Quita de la lista lo ya comprado. Devuelve cuántos artículos quedan.
  Future<int> removePicked(String listId) async {
    await db.delete('list_items', where: 'list_id = ? AND status = ?', whereArgs: [listId, statusPicked]);
    await db.update('list_items', {'status': statusPending}, where: 'list_id = ? AND status = ?',
        whereArgs: [listId, statusUnavailable]);
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM list_items WHERE list_id = ?', [listId]);
    _changed();
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> deleteItem(String itemId) async {
    await db.delete('list_items', where: 'id = ?', whereArgs: [itemId]);
    _changed();
  }

  /// Guarda el precio en la línea y lo registra como observación de precio.
  Future<void> setItemPrice(ListItem item, double? price,
      {String? storeId, bool offer = false, String? validUntil, String source = 'manual'}) async {
    await db.update('list_items', {'price': price}, where: 'id = ?', whereArgs: [item.id]);
    if (price != null && storeId != null) {
      await recordPrice(item.productId, storeId, price,
          offer: offer, validUntil: validUntil, source: source, notify: false);
    }
    _changed();
  }

  // ----------------------------------------------------------------- Precios

  /// Una observación por artículo, tienda y día (la última sustituye).
  Future<void> recordPrice(String productId, String storeId, double price,
      {bool offer = false,
      String source = 'manual',
      bool notify = true,
      String? date,
      String? validUntil}) async {
    final day = date ?? todayIso();
    await db.delete('prices',
        where: 'product_id = ? AND store_id = ? AND date = ?',
        whereArgs: [productId, storeId, day]);
    await db.insert('prices', {
      'id': newId(),
      'product_id': productId,
      'store_id': storeId,
      'price': price,
      'date': day,
      'is_offer': offer ? 1 : 0,
      'source': source,
      'valid_until': validUntil,
      'created_at': _now,
    });
    if (notify) _changed();
  }

  /// Una oferta deja de contar al pasar su fecha de fin; sin fecha, a los 7 días.
  static bool _offerExpired(Map<String, Object?> m, String today) {
    if (((m['is_offer'] as int?) ?? 0) != 1) return false;
    final until = m['valid_until'] as String?;
    if (until != null) return until.compareTo(today) < 0;
    final d = DateTime.tryParse(m['date'] as String);
    if (d == null) return false;
    return DateTime.now().difference(d).inDays > 7;
  }

  /// productId -> último precio válido en esa tienda (ofertas caducadas fuera).
  Future<Map<String, KnownPrice>> knownPrices(String storeId) async {
    final r = await db.query('prices',
        where: 'store_id = ?', whereArgs: [storeId], orderBy: 'date DESC, created_at DESC');
    final today = todayIso();
    final out = <String, KnownPrice>{};
    for (final m in r) {
      final pid = m['product_id'] as String;
      if (out.containsKey(pid) || _offerExpired(m, today)) continue;
      out[pid] = KnownPrice(
        price: (m['price'] as num).toDouble(),
        date: m['date'] as String,
        offer: ((m['is_offer'] as int?) ?? 0) == 1,
      );
    }
    return out;
  }

  Future<Map<String, double>> lastPrices(String storeId) async =>
      (await knownPrices(storeId)).map((k, v) => MapEntry(k, v.price));

  Future<List<PriceEntry>> priceHistory(String productId) async {
    final r = await db.rawQuery('''
      SELECT pr.price, pr.date, pr.is_offer, pr.valid_until, pr.store_id, s.name AS store_name
      FROM prices pr JOIN stores s ON s.id = pr.store_id
      WHERE pr.product_id = ?
      ORDER BY pr.date DESC, pr.created_at DESC
    ''', [productId]);
    return r
        .map((m) => PriceEntry(
              storeId: m['store_id'] as String,
              storeName: m['store_name'] as String,
              price: (m['price'] as num).toDouble(),
              date: m['date'] as String,
              offer: ((m['is_offer'] as int?) ?? 0) == 1,
              validUntil: m['valid_until'] as String?,
            ))
        .toList();
  }

  /// Precio por unidad base (€/kg, €/l, €/ud) o null si no se conoce el formato.
  static ({double value, String unit})? unitPrice(double? unitQty, String? unit, double price) {
    if (unitQty == null || unit == null || unitQty <= 0) return null;
    return (value: price / unitQty, unit: unit);
  }

  /// Para cada artículo pendiente: la tienda cercana más barata si ahorra algo.
  Future<Map<String, ({Store store, double price, double saving})>> cheaperElsewhere(
      String listId, String currentStoreId, List<Store> candidates) async {
    final its = (await items(listId)).where((i) => i.status == statusPending).toList();
    final here = await knownPrices(currentStoreId);
    final others = <Store, Map<String, KnownPrice>>{};
    for (final s in candidates) {
      if (s.id == currentStoreId) continue;
      others[s] = await knownPrices(s.id);
    }
    final out = <String, ({Store store, double price, double saving})>{};
    for (final it in its) {
      final mine = here[it.productId]?.price;
      if (mine == null) continue;
      ({Store store, double price, double saving})? best;
      for (final e in others.entries) {
        final p = e.value[it.productId];
        if (p == null || p.isOld) continue;
        final saving = mine - p.price;
        if (saving > 0.009 && (best == null || saving > best.saving)) {
          best = (store: e.key, price: p.price, saving: saving);
        }
      }
      if (best != null) out[it.id] = best;
    }
    return out;
  }

  /// Plan para repartir lo pendiente entre dos tiendas (cada artículo donde sea
  /// más barato). Solo cuenta artículos con precio en las dos.
  Future<
      ({
        double totalA,
        double totalB,
        double onlyA,
        double onlyB,
        int toA,
        int toB,
        int compared,
        List<String> itemsToB
      })> splitPlan(String listId, String storeA, String storeB) async {
    final its = (await items(listId)).where((i) => i.status == statusPending).toList();
    final pa = await knownPrices(storeA);
    final pb = await knownPrices(storeB);
    var totalA = 0.0, totalB = 0.0, onlyA = 0.0, onlyB = 0.0;
    var toA = 0, toB = 0, compared = 0;
    final itemsToB = <String>[];
    for (final it in its) {
      final a = pa[it.productId]?.price;
      final b = pb[it.productId]?.price;
      if (a == null || b == null) continue;
      compared++;
      onlyA += a * it.qty;
      onlyB += b * it.qty;
      if (b < a) {
        totalB += b * it.qty;
        toB++;
        itemsToB.add(it.id);
      } else {
        totalA += a * it.qty;
        toA++;
      }
    }
    return (
      totalA: totalA,
      totalB: totalB,
      onlyA: onlyA,
      onlyB: onlyB,
      toA: toA,
      toB: toB,
      compared: compared,
      itemsToB: itemsToB,
    );
  }

  /// Mueve líneas a otra lista (crea la lista si hace falta).
  Future<void> moveItems(List<String> itemIds, String toListId) async {
    final batch = db.batch();
    for (final id in itemIds) {
      batch.update('list_items', {'list_id': toListId}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    _changed();
  }

  /// Bajadas de precio recientes de artículos que compras, en las tiendas dadas.
  Future<List<({Product product, Store store, double before, double now, String date})>>
      priceDrops(List<Store> inStores, {int days = 30}) async {
    final out = <({Product product, Store store, double before, double now, String date})>[];
    final bought = await db.rawQuery(
        'SELECT DISTINCT product_id FROM purchase_items WHERE product_id IS NOT NULL');
    final ids = bought.map((m) => m['product_id'] as String).toSet();
    final since = DateTime.now().subtract(Duration(days: days));
    for (final s in inStores) {
      final r = await db.query('prices',
          where: 'store_id = ?', whereArgs: [s.id], orderBy: 'date DESC, created_at DESC');
      final seen = <String, Map<String, Object?>>{};
      final prev = <String, Map<String, Object?>>{};
      for (final m in r) {
        final pid = m['product_id'] as String;
        if (!seen.containsKey(pid)) {
          seen[pid] = m;
        } else if (!prev.containsKey(pid)) {
          prev[pid] = m;
        }
      }
      for (final e in seen.entries) {
        if (ids.isNotEmpty && !ids.contains(e.key)) continue;
        final p0 = prev[e.key];
        if (p0 == null) continue;
        final now = (e.value['price'] as num).toDouble();
        final before = (p0['price'] as num).toDouble();
        final date = e.value['date'] as String;
        final d = DateTime.tryParse(date);
        if (now < before - 0.009 && d != null && d.isAfter(since)) {
          final prod = await productById(e.key);
          if (prod != null) {
            out.add((product: prod, store: s, before: before, now: now, date: date));
          }
        }
      }
    }
    out.sort((a, b) => ((b.before - b.now) / b.before).compareTo((a.before - a.now) / a.before));
    return out;
  }

  // ------------------------------------------------------- Agrupar y estimar

  /// Agrupa las líneas por sección. Sin tienda: secciones generales.
  /// Con tienda: secciones de esa tienda en su orden de recorrido.
  Future<List<SectionGroup>> groups(String listId, String? storeId) async {
    final items = await this.items(listId);
    if (storeId == null) {
      final map = <String, List<ListItem>>{};
      for (final it in items) {
        map.putIfAbsent(it.section, () => []).add(it);
      }
      final out = <SectionGroup>[];
      for (final name in defaultSections) {
        final l = map.remove(name);
        if (l != null) out.add(SectionGroup(name: name, items: l));
      }
      for (final e in map.entries) {
        out.add(SectionGroup(name: e.key, items: e.value));
      }
      return out;
    }

    final secs = await sections(storeId);
    final overrides = await locationsInStore(storeId);
    final bySection = <String, List<ListItem>>{};
    final unplaced = <ListItem>[];
    for (final it in items) {
      final target = resolveSection(it.section, it.productId, secs, overrides);
      if (target == null) {
        unplaced.add(it);
      } else {
        bySection.putIfAbsent(target.id, () => []).add(it);
      }
    }
    final out = <SectionGroup>[];
    for (final s in secs) {
      final l = bySection[s.id];
      if (l != null && l.isNotEmpty) {
        out.add(SectionGroup(sectionId: s.id, name: s.name, items: l));
      }
    }
    if (unplaced.isNotEmpty) {
      out.add(SectionGroup(name: 'Sin sección', items: unplaced));
    }
    return out;
  }

  /// Total estimado de la lista con los últimos precios de una tienda.
  static ({double total, int priced, int count}) estimate(
      List<ListItem> items, Map<String, double> prices) {
    var total = 0.0;
    var priced = 0;
    var count = 0;
    for (final it in items) {
      if (it.status == statusUnavailable) continue;
      count++;
      final p = it.price ?? prices[it.productId];
      if (p != null) {
        final q = it.status == statusPicked ? it.boughtQty : it.qty;
        total += p * q;
        priced++;
      }
    }
    return (total: total, priced: priced, count: count);
  }

  /// Comparativa de lo pendiente entre tiendas (más artículos con precio
  /// primero; a igualdad, menor coste).
  Future<List<StoreEstimate>> compareStores(String listId, {double? lat, double? lng}) async {
    final its = (await items(listId)).where((i) => i.status == statusPending).toList();
    final out = <StoreEstimate>[];
    for (final s in await stores()) {
      final prices = await lastPrices(s.id);
      var total = 0.0;
      var priced = 0;
      for (final it in its) {
        final p = prices[it.productId];
        if (p != null) {
          total += p * it.qty;
          priced++;
        }
      }
      final dist = (lat != null && lng != null && s.hasLocation)
          ? distanceKm(lat, lng, s.lat!, s.lng!)
          : null;
      out.add(StoreEstimate(
          store: s, total: total, priced: priced, count: its.length, distanceKm: dist));
    }
    out.sort((a, b) {
      final cov = b.priced.compareTo(a.priced);
      if (cov != 0) return cov;
      return a.total.compareTo(b.total);
    });
    return out;
  }

  // ------------------------------------------------------ Compras (historial)

  /// Cierra la compra: guarda lo cogido como compra, registra el recorrido y
  /// devuelve el id de la compra (null si no se cogió nada).
  Future<String?> finishShopping(String listId, String storeId) async {
    final store = await storeById(storeId);
    final its = (await items(listId)).where((i) => i.status == statusPicked).toList();
    if (its.isEmpty) return null;
    final prices = await lastPrices(storeId);
    final id = newId();
    final today = todayIso();
    var total = 0.0;
    await db.transaction((t) async {
      for (final it in its) {
        final price = it.price ?? prices[it.productId];
        final amount = price == null ? null : price * it.boughtQty;
        total += amount ?? 0;
        await t.insert('purchase_items', {
          'id': newId(),
          'purchase_id': id,
          'product_id': it.productId,
          'raw_text': it.name,
          'qty': it.boughtQty,
          'unit_price': price,
          'amount': amount,
        });
      }
      await t.insert('purchases', {
        'id': id,
        'list_id': listId,
        'store_id': storeId,
        'store_name': store?.name ?? '',
        'date': today,
        'total': double.parse(total.toStringAsFixed(2)),
        'items_count': its.length,
        'source': 'compra',
        'created_at': _now,
      });
    });

    // Recorrido: orden en que se empezó cada sección (0 = primera, 1 = última).
    final secs = await sections(storeId);
    final overrides = await locationsInStore(storeId);
    final firstPick = <String, int>{};
    for (final it in its) {
      if (it.pickedAt == null) continue;
      final s = resolveSection(it.section, it.productId, secs, overrides);
      if (s == null) continue;
      final cur = firstPick[s.id];
      if (cur == null || it.pickedAt! < cur) firstPick[s.id] = it.pickedAt!;
    }
    if (firstPick.length >= 2) {
      final ordered = firstPick.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      final n = ordered.length - 1;
      await db.delete('route_log',
          where: 'store_id = ? AND date = ?', whereArgs: [storeId, today]);
      for (var i = 0; i < ordered.length; i++) {
        await db.insert('route_log', {
          'id': newId(),
          'store_id': storeId,
          'section_id': ordered[i].key,
          'rank': i / n,
          'date': today,
        });
      }
    }
    _changed();
    return id;
  }

  /// Guarda una compra a partir de un ticket. Registra precios y aprende alias.
  Future<String> saveTicketPurchase({
    required String? storeId,
    required String storeName,
    required String date,
    required double total,
    required List<({String? productId, String raw, double qty, double? unitPrice, double? amount})>
        lines,
    String? imagePath,
  }) async {
    final id = newId();
    final storeKey = storeId ?? storeName.toLowerCase();
    await db.transaction((t) async {
      await t.insert('purchases', {
        'id': id,
        'store_id': storeId,
        'store_name': storeName,
        'date': date,
        'total': total,
        'items_count': lines.length,
        'source': 'ticket',
        'image_path': imagePath,
        'created_at': _now,
      });
      for (final l in lines) {
        await t.insert('purchase_items', {
          'id': newId(),
          'purchase_id': id,
          'product_id': l.productId,
          'raw_text': l.raw,
          'qty': l.qty,
          'unit_price': l.unitPrice,
          'amount': l.amount,
        });
        if (l.productId != null && l.raw.trim().isNotEmpty) {
          await t.insert(
              'aliases',
              {'store_key': storeKey, 'raw_text': normalizeTicketText(l.raw), 'product_id': l.productId},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    if (storeId != null) {
      for (final l in lines) {
        final unit = l.unitPrice ?? (l.amount != null && l.qty > 0 ? l.amount! / l.qty : null);
        if (l.productId != null && unit != null && unit > 0) {
          await recordPrice(l.productId!, storeId, double.parse(unit.toStringAsFixed(2)),
              source: 'ticket', date: date, notify: false);
        }
      }
    }
    _changed();
    return id;
  }

  Future<String?> aliasLookup(String storeKey, String raw) async {
    final r = await db.query('aliases',
        where: 'store_key = ? AND raw_text = ?', whereArgs: [storeKey, normalizeTicketText(raw)]);
    if (r.isNotEmpty) return r.first['product_id'] as String;
    final any = await db.query('aliases',
        where: 'raw_text = ?', whereArgs: [normalizeTicketText(raw)], limit: 1);
    return any.isEmpty ? null : any.first['product_id'] as String;
  }

  Future<List<Purchase>> purchases({String? from, String? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to);
    }
    final r = await db.query('purchases',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'date DESC, created_at DESC');
    return r.map(Purchase.fromMap).toList();
  }

  Future<Purchase?> purchaseById(String id) async {
    final r = await db.query('purchases', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Purchase.fromMap(r.first);
  }

  Future<List<PurchaseItem>> purchaseItems(String purchaseId) async {
    final r = await db.rawQuery('''
      SELECT pi.*, p.name AS pname FROM purchase_items pi
      LEFT JOIN products p ON p.id = pi.product_id
      WHERE pi.purchase_id = ?
    ''', [purchaseId]);
    return r.map(PurchaseItem.fromMap).toList();
  }

  Future<void> updatePurchase(String id,
      {String? warrantyUntil, bool clearWarranty = false, String? imagePath, String? notes}) async {
    final v = <String, Object?>{};
    if (warrantyUntil != null || clearWarranty) v['warranty_until'] = warrantyUntil;
    if (imagePath != null) v['image_path'] = imagePath;
    if (notes != null) v['notes'] = notes;
    if (v.isEmpty) return;
    await db.update('purchases', v, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deletePurchase(String id) async {
    await db.delete('purchases', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Añade a una lista los artículos de una compra anterior.
  Future<int> repeatPurchase(String purchaseId, String listId) async {
    var n = 0;
    for (final pi in await purchaseItems(purchaseId)) {
      if (pi.productId == null) continue;
      final p = await productById(pi.productId!);
      if (p == null) continue;
      await addItem(listId, p, qty: pi.qty <= 0 ? 1 : pi.qty, notify: false);
      n++;
    }
    _changed();
    return n;
  }

  /// Compras con garantía que vence en los próximos [days] días.
  Future<List<Purchase>> warrantiesExpiring({int days = 30}) async {
    final today = todayIso();
    final limit = isoDate(DateTime.now().add(Duration(days: days)));
    final r = await db.query('purchases',
        where: 'warranty_until IS NOT NULL AND warranty_until >= ? AND warranty_until <= ?',
        whereArgs: [today, limit],
        orderBy: 'warranty_until ASC');
    return r.map(Purchase.fromMap).toList();
  }

  Future<double> spentBetween(String from, String to) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(total), 0) AS t FROM purchases WHERE date >= ? AND date <= ?',
        [from, to]);
    return ((r.first['t'] as num?) ?? 0).toDouble();
  }

  Future<double> spentThisMonth() async {
    final now = DateTime.now();
    return spentBetween(isoDate(DateTime(now.year, now.month, 1)), todayIso());
  }

  /// Resumen de gasto de un periodo: total, compras, por tienda y por sección,
  /// y ahorro estimado frente al precio medio de cada artículo.
  Future<
      ({
        double total,
        int count,
        Map<String, double> byStore,
        Map<String, double> bySection,
        double saving
      })> summary(String from, String to) async {
    final ps = await purchases(from: from, to: to);
    final byStore = <String, double>{};
    var total = 0.0;
    for (final p in ps) {
      total += p.total;
      final k = p.storeName.isEmpty ? 'Sin tienda' : p.storeName;
      byStore[k] = (byStore[k] ?? 0) + p.total;
    }
    final r = await db.rawQuery('''
      SELECT COALESCE(p.section, 'Otros') AS section, pi.amount, pi.unit_price, pi.qty, pi.product_id
      FROM purchase_items pi
      JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN products p ON p.id = pi.product_id
      WHERE pu.date >= ? AND pu.date <= ?
    ''', [from, to]);
    final avg = <String, double>{};
    final avgR = await db.rawQuery('SELECT product_id, AVG(price) AS a FROM prices GROUP BY product_id');
    for (final m in avgR) {
      avg[m['product_id'] as String] = (m['a'] as num).toDouble();
    }
    final bySection = <String, double>{};
    var saving = 0.0;
    for (final m in r) {
      final amount = (m['amount'] as num?)?.toDouble() ?? 0;
      final s = m['section'] as String;
      bySection[s] = (bySection[s] ?? 0) + amount;
      final pid = m['product_id'] as String?;
      final unitP = (m['unit_price'] as num?)?.toDouble();
      final qty = ((m['qty'] as num?) ?? 1).toDouble();
      if (pid != null && unitP != null && avg[pid] != null) {
        saving += (avg[pid]! - unitP) * qty;
      }
    }
    return (
      total: total,
      count: ps.length,
      byStore: byStore,
      bySection: bySection,
      saving: saving,
    );
  }

  // -------------------------------------------------------------- Habituales

  /// Artículos comprados al menos dos veces, con su frecuencia media.
  Future<List<Habitual>> habituals() async {
    final r = await db.rawQuery('''
      SELECT pi.product_id AS pid, pu.date AS date
      FROM purchase_items pi JOIN purchases pu ON pu.id = pi.purchase_id
      WHERE pi.product_id IS NOT NULL
      ORDER BY pu.date ASC
    ''');
    final dates = <String, List<String>>{};
    for (final m in r) {
      final pid = m['pid'] as String;
      final d = m['date'] as String;
      final l = dates.putIfAbsent(pid, () => []);
      if (l.isEmpty || l.last != d) l.add(d);
    }
    final out = <Habitual>[];
    for (final e in dates.entries) {
      if (e.value.length < 2) continue;
      final p = await productById(e.key);
      if (p == null) continue;
      final first = DateTime.parse(e.value.first);
      final last = DateTime.parse(e.value.last);
      final every = last.difference(first).inDays / (e.value.length - 1);
      out.add(Habitual(
        product: p,
        times: e.value.length,
        lastDate: e.value.last,
        everyDays: every < 1 ? 1 : every,
      ));
    }
    out.sort((a, b) {
      if (a.isDue != b.isDue) return a.isDue ? -1 : 1;
      return b.times.compareTo(a.times);
    });
    return out;
  }

  // ------------------------------------------------------- Tarjetas y cupones

  Future<List<LoyaltyCard>> cards() async {
    final r = await db.query('cards', orderBy: 'name COLLATE NOCASE');
    return r.map(LoyaltyCard.fromMap).toList();
  }

  Future<void> saveCard(
      {String? id, required String name, required String code, required String format, String notes = ''}) async {
    await db.insert(
        'cards',
        {
          'id': id ?? newId(),
          'name': name,
          'code': code,
          'format': format,
          'notes': notes,
          'created_at': _now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  Future<void> deleteCard(String id) async {
    await db.delete('cards', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<Coupon>> coupons({bool includeUsed = false}) async {
    final r = await db.query('coupons',
        where: includeUsed ? null : 'used = 0', orderBy: 'expires IS NULL, expires ASC');
    return r.map(Coupon.fromMap).toList();
  }

  Future<void> saveCoupon({
    String? id,
    required String storeName,
    required String description,
    String code = '',
    String? expires,
  }) async {
    await db.insert(
        'coupons',
        {
          'id': id ?? newId(),
          'store_name': storeName,
          'description': description,
          'code': code,
          'expires': expires,
          'used': 0,
          'created_at': _now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  Future<void> setCouponUsed(String id, bool used) async {
    await db.update('coupons', {'used': used ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteCoupon(String id) async {
    await db.delete('coupons', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // -------------------------------------------------------- Copia de seguridad

  Future<Map<String, Object?>> exportAll() async {
    final data = <String, Object?>{};
    for (final t in allTables) {
      data[t] = await db.query(t);
    }
    return {
      'app': 'CompraClara',
      'format': 1,
      'schema': 3,
      'exported_at': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  /// Sustituye todos los datos por los de la copia. Lanza FormatException si no es válida.
  Future<int> importAll(Map<String, Object?> backup) async {
    if (backup['app'] != 'CompraClara' || backup['data'] is! Map) {
      throw const FormatException('El archivo no es una copia de CompraClara');
    }
    final data = backup['data'] as Map;
    var rows = 0;
    await db.transaction((t) async {
      for (final table in allTables.reversed) {
        await t.delete(table);
      }
      for (final table in allTables) {
        final list = data[table];
        if (list is! List) continue;
        for (final row in list) {
          if (row is Map) {
            await t.insert(table, Map<String, Object?>.from(row),
                conflictAlgorithm: ConflictAlgorithm.replace);
            rows++;
          }
        }
      }
    });
    _changed();
    return rows;
  }

  /// CSV de compras (una fila por artículo comprado).
  Future<String> purchasesCsv() async {
    final r = await db.rawQuery('''
      SELECT pu.date, pu.store_name, COALESCE(p.name, pi.raw_text) AS item, p.section,
             pi.qty, pi.unit_price, pi.amount, pu.total, pu.source
      FROM purchase_items pi
      JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN products p ON p.id = pi.product_id
      ORDER BY pu.date DESC
    ''');
    final b = StringBuffer('fecha;tienda;articulo;seccion;cantidad;precio_unitario;importe;total_compra;origen\n');
    for (final m in r) {
      b.writeln([
        m['date'],
        m['store_name'],
        m['item'],
        m['section'] ?? '',
        csvNum(m['qty']),
        csvNum(m['unit_price']),
        csvNum(m['amount']),
        csvNum(m['total']),
        m['source'],
      ].map(csvCell).join(';'));
    }
    return b.toString();
  }

  /// CSV de precios registrados.
  Future<String> pricesCsv() async {
    final r = await db.rawQuery('''
      SELECT pr.date, s.name AS store, p.name AS item, p.brand, p.size, pr.price, pr.is_offer, pr.source
      FROM prices pr JOIN products p ON p.id = pr.product_id JOIN stores s ON s.id = pr.store_id
      ORDER BY pr.date DESC
    ''');
    final b = StringBuffer('fecha;tienda;articulo;marca;formato;precio;oferta;origen\n');
    for (final m in r) {
      b.writeln([
        m['date'],
        m['store'],
        m['item'],
        m['brand'],
        m['size'],
        csvNum(m['price']),
        ((m['is_offer'] as int?) ?? 0) == 1 ? 'sí' : 'no',
        m['source'],
      ].map(csvCell).join(';'));
    }
    return b.toString();
  }
}
