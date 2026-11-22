class Store {
  Store({required this.id, required this.name, this.chain = '', this.lat, this.lng});

  final String id;
  final String name;
  final String chain;
  final double? lat;
  final double? lng;

  bool get hasLocation => lat != null && lng != null;

  factory Store.fromMap(Map<String, Object?> m) => Store(
        id: m['id'] as String,
        name: m['name'] as String,
        chain: (m['chain'] as String?) ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
}

class StoreSection {
  StoreSection({
    required this.id,
    required this.storeId,
    required this.name,
    required this.position,
    required this.hidden,
  });

  final String id;
  final String storeId;
  final String name;
  final int position;
  final bool hidden;

  factory StoreSection.fromMap(Map<String, Object?> m) => StoreSection(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        name: m['name'] as String,
        position: (m['position'] as int?) ?? 0,
        hidden: ((m['hidden'] as int?) ?? 0) == 1,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    this.brand = '',
    this.size = '',
    this.section = 'Otros',
    this.notes = '',
  });

  final String id;
  String name;
  String brand;
  String size;
  String section;
  String notes;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        brand: (m['brand'] as String?) ?? '',
        size: (m['size'] as String?) ?? '',
        section: (m['section'] as String?) ?? 'Otros',
        notes: (m['notes'] as String?) ?? '',
      );

  /// "Marca · 1 L"
  String get detail {
    final parts = [brand, size].where((s) => s.trim().isNotEmpty).toList();
    return parts.join(' · ');
  }
}

class ShoppingList {
  ShoppingList({
    required this.id,
    required this.name,
    this.storeId,
    this.budget,
    this.archived = false,
    this.total = 0,
    this.picked = 0,
  });

  final String id;
  final String name;
  final String? storeId;
  final double? budget;
  final bool archived;
  final int total;
  final int picked;

  factory ShoppingList.fromMap(Map<String, Object?> m) => ShoppingList(
        id: m['id'] as String,
        name: m['name'] as String,
        storeId: m['store_id'] as String?,
        budget: (m['budget'] as num?)?.toDouble(),
        archived: ((m['archived'] as int?) ?? 0) == 1,
        total: (m['total'] as int?) ?? 0,
        picked: (m['picked'] as int?) ?? 0,
      );
}

/// Estados de una línea de lista.
const int statusPending = 0;
const int statusPicked = 1;
const int statusUnavailable = 2;

class ListItem {
  ListItem({
    required this.id,
    required this.listId,
    required this.productId,
    required this.qty,
    required this.note,
    required this.status,
    required this.price,
    required this.position,
    required this.name,
    required this.brand,
    required this.size,
    required this.section,
  });

  final String id;
  final String listId;
  final String productId;
  final double qty;
  final String note;
  final int status;
  final double? price;
  final int position;
  final String name;
  final String brand;
  final String size;
  final String section;

  String get detail {
    final parts = [brand, size].where((s) => s.trim().isNotEmpty).toList();
    return parts.join(' · ');
  }

  factory ListItem.fromMap(Map<String, Object?> m) => ListItem(
        id: m['id'] as String,
        listId: m['list_id'] as String,
        productId: m['product_id'] as String,
        qty: (m['qty'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        status: (m['status'] as int?) ?? 0,
        price: (m['price'] as num?)?.toDouble(),
        position: (m['position'] as int?) ?? 0,
        name: (m['pname'] as String?) ?? '(artículo borrado)',
        brand: (m['pbrand'] as String?) ?? '',
        size: (m['psize'] as String?) ?? '',
        section: (m['psection'] as String?) ?? 'Otros',
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'list_id': listId,
        'product_id': productId,
        'qty': qty,
        'note': note,
        'status': status,
        'price': price,
        'position': position,
      };
}

/// Grupo de artículos de una sección (en el orden del recorrido).
class SectionGroup {
  SectionGroup({this.sectionId, required this.name, required this.items});

  final String? sectionId;
  final String name;
  final List<ListItem> items;

  int get pendingCount => items.where((i) => i.status == statusPending).length;
  int get pickedCount => items.where((i) => i.status == statusPicked).length;
  int get activeCount => items.where((i) => i.status != statusUnavailable).length;
  bool get complete => pendingCount == 0;
}

class PriceEntry {
  PriceEntry({
    required this.storeName,
    required this.price,
    required this.date,
    required this.offer,
  });

  final String storeName;
  final double price;
  final String date;
  final bool offer;
}

class StoreEstimate {
  StoreEstimate({
    required this.store,
    required this.total,
    required this.priced,
    required this.count,
    this.distanceKm,
  });

  final Store store;
  final double total;
  final int priced;
  final int count;

  /// Distancia al punto de referencia (null si la tienda no tiene ubicación).
  final double? distanceKm;
}
