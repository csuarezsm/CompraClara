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

  /// Crea la tienda con la plantilla de secciones.
  Future<Store> addStore(String name, {String chain = ''}) async {
    final id = newId();
    await db.transaction((t) async {
      await t.insert('stores', {
        'id': id,
        'name': name,
        'chain': chain,
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
    return Store(id: id, name: name, chain: chain);
  }

  Future<void> renameStore(String id, String name) async {
    await db.update('stores', {'name': name}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteStore(String id) async {
    await db.delete('stores', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

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

  Future<Product> createProduct({
    required String name,
    String brand = '',
    String size = '',
    String? section,
    String notes = '',
  }) async {
    final p = Product(
      id: newId(),
      name: name.trim(),
      brand: brand.trim(),
      size: size.trim(),
      section: section ?? guessSection(name),
      notes: notes.trim(),
    );
    await db.insert('products', {
      'id': p.id,
      'name': p.name,
      'brand': p.brand,
      'size': p.size,
      'section': p.section,
      'notes': p.notes,
      'created_at': _now,
    });
    _changed();
    return p;
  }

  Future<void> updateProduct(Product p) async {
    await db.update(
      'products',
      {
        'name': p.name.trim(),
        'brand': p.brand.trim(),
        'size': p.size.trim(),
        'section': p.section,
        'notes': p.notes.trim(),
      },
      where: 'id = ?',
      whereArgs: [p.id],
    );
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

  Future<List<ShoppingList>> lists({bool archived = false}) async {
    final r = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id) AS total,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id AND i.status = 1) AS picked
      FROM lists l
      WHERE l.archived = ?
      ORDER BY l.created_at DESC
    ''', [archived ? 1 : 0]);
    return r.map(ShoppingList.fromMap).toList();
  }

  Future<ShoppingList?> listById(String id) async {
    final r = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id) AS total,
        (SELECT COUNT(*) FROM list_items i WHERE i.list_id = l.id AND i.status = 1) AS picked
      FROM lists l WHERE l.id = ?
    ''', [id]);
    return r.isEmpty ? null : ShoppingList.fromMap(r.first);
  }

  Future<ShoppingList> createList(String name, {String? storeId}) async {
    final id = newId();
    await db.insert('lists', {
      'id': id,
      'name': name,
      'store_id': storeId,
      'archived': 0,
      'created_at': _now,
    });
    _changed();
    return ShoppingList(id: id, name: name, storeId: storeId);
  }

  Future<void> renameList(String id, String name) async {
    await db.update('lists', {'name': name}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setListStore(String id, String? storeId) async {
    await db.update('lists', {'store_id': storeId}, where: 'id = ?', whereArgs: [id]);
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
    await db.update('list_items', {'status': statusPending, 'price': null},
        where: 'list_id = ?', whereArgs: [listId]);
    _changed();
  }

  // ------------------------------------------------------ Líneas de la lista

  Future<List<ListItem>> items(String listId) async {
    final r = await db.rawQuery('''
      SELECT i.*, p.name AS pname, p.brand AS pbrand, p.size AS psize, p.section AS psection
      FROM list_items i LEFT JOIN products p ON p.id = i.product_id
      WHERE i.list_id = ?
      ORDER BY i.position ASC
    ''', [listId]);
    return r.map(ListItem.fromMap).toList();
  }

  /// Añade un artículo. Si ya está pendiente en la lista, suma la cantidad
  /// y devuelve true (nunca se duplica).
  Future<bool> addItem(String listId, Product product, {double qty = 1}) async {
    final existing = await db.query(
      'list_items',
      where: 'list_id = ? AND product_id = ? AND status = ?',
      whereArgs: [listId, product.id, statusPending],
    );
    if (existing.isNotEmpty) {
      final cur = (existing.first['qty'] as num).toDouble();
      await db.update('list_items', {'qty': cur + qty},
          where: 'id = ?', whereArgs: [existing.first['id']]);
      _changed();
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
      'note': '',
      'status': statusPending,
      'position': pos,
    });
    _changed();
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
    await db.update('list_items', {'status': status}, where: 'id = ?', whereArgs: [itemId]);
    _changed();
  }

  Future<void> deleteItem(String itemId) async {
    await db.delete('list_items', where: 'id = ?', whereArgs: [itemId]);
    _changed();
  }

  /// Guarda el precio en la línea y lo registra como observación de precio.
  Future<void> setItemPrice(ListItem item, double? price,
      {String? storeId, bool offer = false}) async {
    await db.update('list_items', {'price': price}, where: 'id = ?', whereArgs: [item.id]);
    if (price != null && storeId != null) {
      await recordPrice(item.productId, storeId, price, offer: offer, notify: false);
    }
    _changed();
  }

  // ----------------------------------------------------------------- Precios

  /// Una observación por artículo, tienda y día (la última sustituye).
  Future<void> recordPrice(String productId, String storeId, double price,
      {bool offer = false, String source = 'manual', bool notify = true}) async {
    final today = todayIso();
    await db.delete('prices',
        where: 'product_id = ? AND store_id = ? AND date = ?',
        whereArgs: [productId, storeId, today]);
    await db.insert('prices', {
      'id': newId(),
      'product_id': productId,
      'store_id': storeId,
      'price': price,
      'date': today,
      'is_offer': offer ? 1 : 0,
      'source': source,
      'created_at': _now,
    });
    if (notify) _changed();
  }

  /// productId -> último precio conocido en esa tienda.
  Future<Map<String, double>> lastPrices(String storeId) async {
    final r = await db.query('prices',
        where: 'store_id = ?', whereArgs: [storeId], orderBy: 'date DESC, created_at DESC');
    final out = <String, double>{};
    for (final m in r) {
      final pid = m['product_id'] as String;
      out.putIfAbsent(pid, () => (m['price'] as num).toDouble());
    }
    return out;
  }

  Future<List<PriceEntry>> priceHistory(String productId) async {
    final r = await db.rawQuery('''
      SELECT pr.price, pr.date, pr.is_offer, s.name AS store_name
      FROM prices pr JOIN stores s ON s.id = pr.store_id
      WHERE pr.product_id = ?
      ORDER BY pr.date DESC, pr.created_at DESC
    ''', [productId]);
    return r
        .map((m) => PriceEntry(
              storeName: m['store_name'] as String,
              price: (m['price'] as num).toDouble(),
              date: m['date'] as String,
              offer: ((m['is_offer'] as int?) ?? 0) == 1,
            ))
        .toList();
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
        total += p * it.qty;
        priced++;
      }
    }
    return (total: total, priced: priced, count: count);
  }

  /// Comparativa de la lista entre todas las tiendas (menor coste primero,
  /// priorizando las que tienen más artículos con precio).
  Future<List<StoreEstimate>> compareStores(String listId) async {
    final items = (await this.items(listId)).where((i) => i.status == statusPending).toList();
    final out = <StoreEstimate>[];
    for (final s in await stores()) {
      final prices = await lastPrices(s.id);
      final e = estimate(items.map((i) => ListItem(
            id: i.id,
            listId: i.listId,
            productId: i.productId,
            qty: i.qty,
            note: i.note,
            status: i.status,
            price: null,
            position: i.position,
            name: i.name,
            brand: i.brand,
            size: i.size,
            section: i.section,
          )).toList(), prices);
      out.add(StoreEstimate(store: s, total: e.total, priced: e.priced, count: e.count));
    }
    out.sort((a, b) {
      final cov = b.priced.compareTo(a.priced);
      if (cov != 0) return cov;
      return a.total.compareTo(b.total);
    });
    return out;
  }
}
