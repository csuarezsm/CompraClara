import 'dart:convert';

import 'package:http/http.dart' as http;

class OffProduct {
  OffProduct({
    required this.name,
    required this.brand,
    required this.quantity,
    required this.categories,
    required this.allergens,
    required this.nutriscore,
    required this.labels,
  });

  final String name;
  final String brand;
  final String quantity;
  final List<String> categories;

  /// Claves sin prefijo de idioma: gluten, milk…
  final List<String> allergens;

  /// a, b, c, d, e o vacío.
  final String nutriscore;

  /// Claves sin prefijo: vegan, vegetarian, no-gluten, organic…
  final List<String> labels;
}

/// Consulta la base abierta Open Food Facts por código de barras.
class OffService {
  static List<String> _tags(Object? v) {
    if (v is! List) return const [];
    return v.map((e) {
      final s = e.toString();
      final i = s.indexOf(':');
      return i >= 0 ? s.substring(i + 1) : s;
    }).toList();
  }

  static Future<OffProduct?> lookup(String ean) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$ean.json',
      {
        'fields':
            'product_name,product_name_es,brands,quantity,categories_tags,allergens_tags,nutriscore_grade,labels_tags'
      },
    );
    final r = await http
        .get(uri, headers: {'User-Agent': 'CompraClara/0.2 (info@itcanarias.com)'})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map || j['status'] != 1) return null;
    final p = j['product'];
    if (p is! Map) return null;
    final es = (p['product_name_es'] as String?)?.trim() ?? '';
    final name = es.isNotEmpty ? es : ((p['product_name'] as String?)?.trim() ?? '');
    if (name.isEmpty) return null;
    final brands = (p['brands'] as String?)?.trim() ?? '';
    final grade = (p['nutriscore_grade'] as String?)?.trim().toLowerCase() ?? '';
    return OffProduct(
      name: name,
      brand: brands.split(',').first.trim(),
      quantity: (p['quantity'] as String?)?.trim() ?? '',
      categories: _tags(p['categories_tags']),
      allergens: _tags(p['allergens_tags']),
      nutriscore: 'abcde'.contains(grade) && grade.length == 1 ? grade : '',
      labels: _tags(p['labels_tags']),
    );
  }
}
