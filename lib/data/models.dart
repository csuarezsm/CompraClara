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
    this.unitQty,
    this.unit,
    this.allergens = '',
    this.nutriscore = '',
    this.labels = '',
  });

  final String id;
  String name;
  String brand;
  String size;
  String section;
  String notes;

  /// Cantidad en unidad base (kg, l o ud) para el precio por unidad.
  double? unitQty;
  String? unit;

  /// Alérgenos separados por coma (gluten,leche…), Nutri-Score (a-e) y etiquetas (vegano…).
  String allergens;
  String nutriscore;
  String labels;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        brand: (m['brand'] as String?) ?? '',
        size: (m['size'] as String?) ?? '',
        section: (m['section'] as String?) ?? 'Otros',
        notes: (m['notes'] as String?) ?? '',
        unitQty: (m['unit_qty'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        allergens: (m['allergens'] as String?) ?? '',
        nutriscore: (m['nutriscore'] as String?) ?? '',
        labels: (m['labels'] as String?) ?? '',
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
    this.isTemplate = false,
    this.total = 0,
    this.picked = 0,
  });

  final String id;
  final String name;
  final String? storeId;
  final double? budget;
  final bool archived;
  final bool isTemplate;
  final int total;
  final int picked;

  factory ShoppingList.fromMap(Map<String, Object?> m) => ShoppingList(
        id: m['id'] as String,
        name: m['name'] as String,
        storeId: m['store_id'] as String?,
        budget: (m['budget'] as num?)?.toDouble(),
        archived: ((m['archived'] as int?) ?? 0) == 1,
        isTemplate: ((m['is_template'] as int?) ?? 0) == 1,
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
    this.pickedQty,
    this.pickedAt,
    this.allergens = '',
    this.labels = '',
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

  /// Cantidad cogida si fue parcial (null = la pedida).
  final double? pickedQty;
  final int? pickedAt;
  final String allergens;
  final String labels;

  /// Cantidad que realmente se compra.
  double get boughtQty => status == statusPicked ? (pickedQty ?? qty) : 0;

  bool get isPartial => pickedQty != null && pickedQty! < qty;

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
        pickedQty: (m['picked_qty'] as num?)?.toDouble(),
        pickedAt: m['picked_at'] as int?,
        allergens: (m['pallergens'] as String?) ?? '',
        labels: (m['plabels'] as String?) ?? '',
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
        'picked_qty': pickedQty,
        'picked_at': pickedAt,
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
    required this.storeId,
    required this.storeName,
    required this.price,
    required this.date,
    required this.offer,
    this.validUntil,
  });

  final String storeId;
  final String storeName;
  final double price;
  final String date;
  final bool offer;
  final String? validUntil;
}

/// Último precio útil de un artículo en una tienda, con su antigüedad.
class KnownPrice {
  KnownPrice({required this.price, required this.date, required this.offer});

  final double price;
  final String date;
  final bool offer;

  int get ageDays {
    final d = DateTime.tryParse(date);
    if (d == null) return 0;
    return DateTime.now().difference(d).inDays;
  }

  bool get isOld => ageDays > 90;
  bool get isStale => ageDays > 30;
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

class Purchase {
  Purchase({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.date,
    required this.total,
    required this.itemsCount,
    required this.source,
    this.listId,
    this.imagePath,
    this.warrantyUntil,
    this.notes = '',
  });

  final String id;
  final String? listId;
  final String? storeId;
  final String storeName;
  final String date;
  final double total;
  final int itemsCount;
  final String source;
  final String? imagePath;
  final String? warrantyUntil;
  final String notes;

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as String,
        listId: m['list_id'] as String?,
        storeId: m['store_id'] as String?,
        storeName: (m['store_name'] as String?) ?? '',
        date: m['date'] as String,
        total: ((m['total'] as num?) ?? 0).toDouble(),
        itemsCount: (m['items_count'] as int?) ?? 0,
        source: (m['source'] as String?) ?? 'compra',
        imagePath: m['image_path'] as String?,
        warrantyUntil: m['warranty_until'] as String?,
        notes: (m['notes'] as String?) ?? '',
      );
}

class PurchaseItem {
  PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.rawText,
    required this.qty,
    required this.unitPrice,
    required this.amount,
    this.productName,
  });

  final String id;
  final String purchaseId;
  final String? productId;
  final String rawText;
  final double qty;
  final double? unitPrice;
  final double? amount;
  final String? productName;

  String get label => productName ?? rawText;

  factory PurchaseItem.fromMap(Map<String, Object?> m) => PurchaseItem(
        id: m['id'] as String,
        purchaseId: m['purchase_id'] as String,
        productId: m['product_id'] as String?,
        rawText: (m['raw_text'] as String?) ?? '',
        qty: ((m['qty'] as num?) ?? 1).toDouble(),
        unitPrice: (m['unit_price'] as num?)?.toDouble(),
        amount: (m['amount'] as num?)?.toDouble(),
        productName: m['pname'] as String?,
      );
}

/// Artículo habitual calculado a partir del historial de compras.
class Habitual {
  Habitual({
    required this.product,
    required this.times,
    required this.lastDate,
    required this.everyDays,
  });

  final Product product;
  final int times;
  final String lastDate;

  /// Frecuencia media en días (null si solo hay una compra).
  final double? everyDays;

  int get daysSince {
    final d = DateTime.tryParse(lastDate);
    return d == null ? 0 : DateTime.now().difference(d).inDays;
  }

  bool get isDue => everyDays != null && daysSince >= (everyDays! * 0.9).floor();
}

class LoyaltyCard {
  LoyaltyCard({
    required this.id,
    required this.name,
    required this.code,
    required this.format,
    this.notes = '',
  });

  final String id;
  final String name;
  final String code;
  final String format;
  final String notes;

  factory LoyaltyCard.fromMap(Map<String, Object?> m) => LoyaltyCard(
        id: m['id'] as String,
        name: m['name'] as String,
        code: m['code'] as String,
        format: (m['format'] as String?) ?? 'ean13',
        notes: (m['notes'] as String?) ?? '',
      );
}

class Coupon {
  Coupon({
    required this.id,
    required this.storeName,
    required this.description,
    required this.code,
    required this.expires,
    required this.used,
  });

  final String id;
  final String storeName;
  final String description;
  final String code;
  final String? expires;
  final bool used;

  int? get daysLeft {
    if (expires == null) return null;
    final d = DateTime.tryParse(expires!);
    if (d == null) return null;
    final today = DateTime.now();
    return d.difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  factory Coupon.fromMap(Map<String, Object?> m) => Coupon(
        id: m['id'] as String,
        storeName: (m['store_name'] as String?) ?? '',
        description: m['description'] as String,
        code: (m['code'] as String?) ?? '',
        expires: m['expires'] as String?,
        used: ((m['used'] as int?) ?? 0) == 1,
      );
}
