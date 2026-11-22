import 'dart:convert';

import 'package:http/http.dart' as http;

class OffProduct {
  OffProduct({
    required this.name,
    required this.brand,
    required this.quantity,
    required this.categories,
  });

  final String name;
  final String brand;
  final String quantity;
  final List<String> categories;
}

/// Consulta la base abierta Open Food Facts por código de barras.
class OffService {
  static Future<OffProduct?> lookup(String ean) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$ean.json',
      {'fields': 'product_name,brands,quantity,categories_tags'},
    );
    final r = await http
        .get(uri, headers: {'User-Agent': 'CompraClara/0.1 (info@itcanarias.com)'})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map || j['status'] != 1) return null;
    final p = j['product'];
    if (p is! Map) return null;
    final name = (p['product_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    final brands = (p['brands'] as String?)?.trim() ?? '';
    final tags = (p['categories_tags'] is List)
        ? (p['categories_tags'] as List).map((e) => e.toString()).toList()
        : <String>[];
    return OffProduct(
      name: name,
      brand: brands.split(',').first.trim(),
      quantity: (p['quantity'] as String?)?.trim() ?? '',
      categories: tags,
    );
  }
}
