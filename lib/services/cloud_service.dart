import 'dart:convert';

import 'package:http/http.dart' as http;

import '../main.dart' show repo;
import '../util.dart';
import 'nearby.dart';

class CloudException implements Exception {
  CloudException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cuenta, copia en la nube y precios compartidos con el servidor de CompraClara.
class CloudService {
  static const defaultUrl = 'https://compraclara.itcanarias.com';

  static Future<String> baseUrl() async {
    final u = (await repo.getSetting('cloud_url'))?.trim();
    final url = (u == null || u.isEmpty) ? defaultUrl : u;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Future<String?> token() => repo.getSetting('cloud_token');
  static Future<String?> email() => repo.getSetting('cloud_email');
  static Future<bool> loggedIn() async => (await token()) != null;

  static Future<bool> sharePrices() async => (await repo.getSetting('share_prices')) != '0';
  static Future<bool> useCommunity() async => (await repo.getSetting('use_community')) != '0';

  static Future<Map<String, dynamic>> _call(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) async {
    final base = await baseUrl();
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final t = await token();
      if (t == null) throw CloudException('Inicia sesión primero');
      headers['Authorization'] = 'Bearer $t';
    }
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
    } catch (e) {
      throw CloudException('No se pudo conectar con el servidor ($base)');
    }
    Map<String, dynamic> j;
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      j = d is Map<String, dynamic> ? d : {'data': d};
    } catch (_) {
      j = {};
    }
    if (r.statusCode == 401 && auth) {
      await logout();
      throw CloudException('La sesión ha caducado. Vuelve a entrar.');
    }
    if (r.statusCode >= 400) {
      throw CloudException((j['error'] as String?) ?? 'Error del servidor (${r.statusCode})');
    }
    return j;
  }

  static Future<bool> health() async {
    try {
      final j = await _call('GET', '/v1/health', auth: false);
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _saveSession(Map<String, dynamic> j) async {
    await repo.setSetting('cloud_token', j['token'] as String);
    await repo.setSetting('cloud_email', j['email'] as String);
  }

  static Future<void> register(String email, String password) async =>
      _saveSession(await _call('POST', '/v1/auth/register',
          body: {'email': email, 'password': password}, auth: false));

  static Future<void> login(String email, String password) async =>
      _saveSession(await _call('POST', '/v1/auth/login', body: {'email': email, 'password': password}, auth: false));

  static Future<void> logout() async {
    await repo.setSetting('cloud_token', null);
    await repo.setSetting('cloud_email', null);
  }

  static Future<void> deleteAccount() async {
    await _call('DELETE', '/v1/account');
    await logout();
  }

  // ------------------------------------------------------------ Copia

  static Future<void> uploadBackup() async {
    await _call('PUT', '/v1/backup', body: await repo.exportAll());
    await repo.setSetting('last_cloud_backup', DateTime.now().toIso8601String());
  }

  static Future<String?> backupDate() async {
    final j = await _call('GET', '/v1/backup/info');
    return j['exists'] == true ? j['updated_at'] as String? : null;
  }

  static Future<int> restoreBackup() async {
    final j = await _call('GET', '/v1/backup');
    final b = j['backup'];
    if (b is! Map) throw CloudException('Copia no válida');
    final token = await repo.getSetting('cloud_token');
    final mail = await repo.getSetting('cloud_email');
    final n = await repo.importAll(Map<String, Object?>.from(b));
    // La sesión se mantiene aunque la copia sea de antes de iniciar sesión.
    if (token != null) await repo.setSetting('cloud_token', token);
    if (mail != null) await repo.setSetting('cloud_email', mail);
    return n;
  }

  // ---------------------------------------------------- Precios compartidos

  /// Envía los precios nuevos de artículos con código de barras en tiendas con ubicación.
  static Future<int> pushPrices() async {
    if (!await sharePrices()) return 0;
    final since = int.tryParse(await repo.getSetting('last_push') ?? '') ?? 0;
    final rows = await repo.db.rawQuery('''
      SELECT pr.price, pr.date, pr.is_offer, pr.valid_until, pr.source, pr.created_at,
             p.name, p.brand, p.size, s.name AS store_name, s.lat, s.lng,
             (SELECT ean FROM barcodes b WHERE b.product_id = p.id LIMIT 1) AS ean
      FROM prices pr
      JOIN products p ON p.id = pr.product_id
      JOIN stores s ON s.id = pr.store_id
      WHERE pr.created_at > ? AND pr.source <> 'comunidad'
        AND s.lat IS NOT NULL AND s.lng IS NOT NULL AND s.chain <> 'ejemplo'
      ORDER BY pr.created_at ASC
      LIMIT 500
    ''', [since]);
    final items = [
      for (final r in rows)
        if (r['ean'] != null)
          {
            'ean': r['ean'],
            'name': r['name'],
            'brand': r['brand'],
            'size': r['size'],
            'store': {'name': r['store_name'], 'lat': r['lat'], 'lng': r['lng']},
            'price': r['price'],
            'is_offer': r['is_offer'] == 1,
            'valid_until': r['valid_until'],
            'date': r['date'],
            'source': r['source'],
          }
    ];
    var accepted = 0;
    if (items.isNotEmpty) {
      final j = await _call('POST', '/v1/prices', body: {'prices': items});
      accepted = (j['accepted'] as num?)?.toInt() ?? 0;
    }
    if (rows.isNotEmpty) {
      await repo.setSetting('last_push', '${rows.last['created_at']}');
    }
    return accepted;
  }

  /// Descarga precios de la comunidad cerca y los guarda como precios de las
  /// tiendas locales (creando las tiendas que falten). Nunca pisa un precio propio
  /// igual o más reciente.
  static Future<int> pullPrices() async {
    if (!await useCommunity()) return 0;
    final ref = await referencePoint();
    if (ref == null) throw CloudException('Activa el GPS o fija tu zona habitual en Ajustes');
    final radius = await repo.radiusKm();
    final eanRows = await repo.db.rawQuery('SELECT ean, product_id FROM barcodes LIMIT 300');
    if (eanRows.isEmpty) return 0;
    final productOf = {for (final r in eanRows) r['ean'] as String: r['product_id'] as String};
    final j = await _call('GET', '/v1/prices', query: {
      'lat': '${ref.lat}',
      'lng': '${ref.lng}',
      'radius_km': radius.toStringAsFixed(0),
      'eans': productOf.keys.join(','),
    });
    final list = (j['prices'] as List?) ?? const [];
    final stores = await repo.stores();
    var applied = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final pid = productOf[e['ean']];
      final st = e['store'];
      if (pid == null || st is! Map) continue;
      final lat = (st['lat'] as num).toDouble();
      final lng = (st['lng'] as num).toDouble();
      String? storeId;
      for (final s in stores) {
        if (s.hasLocation && distanceKm(lat, lng, s.lat!, s.lng!) <= 0.15) {
          storeId = s.id;
          break;
        }
      }
      if (storeId == null) {
        final s = await repo.addStore(st['name'] as String, chain: 'comunidad');
        await repo.setStoreLocation(s.id, lat, lng);
        stores.add((await repo.storeById(s.id))!);
        storeId = s.id;
      }
      final date = e['date'] as String;
      final newer = await repo.db.query('prices',
          where: 'product_id = ? AND store_id = ? AND date >= ?', whereArgs: [pid, storeId, date], limit: 1);
      if (newer.isNotEmpty) continue;
      await repo.db.insert('prices', {
        'id': newId(),
        'product_id': pid,
        'store_id': storeId,
        'price': (e['price'] as num).toDouble(),
        'date': date,
        'is_offer': e['offer'] == true ? 1 : 0,
        'source': 'comunidad',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      applied++;
    }
    repo.refresh();
    return applied;
  }

  /// Sincroniza (envía y recibe). Devuelve un resumen legible.
  static Future<String> sync() async {
    final sent = await pushPrices();
    final got = await pullPrices();
    await repo.setSetting('last_sync', DateTime.now().toIso8601String());
    return 'Enviados $sent precios · recibidos $got de la comunidad';
  }

  /// Sincroniza en segundo plano si hace más de 6 horas (al abrir la app).
  static Future<void> autoSync() async {
    try {
      if (!await loggedIn()) return;
      final last = DateTime.tryParse(await repo.getSetting('last_sync') ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 6) return;
      await sync();
      final lastBackup = DateTime.tryParse(await repo.getSetting('last_cloud_backup') ?? '');
      if (lastBackup == null || DateTime.now().difference(lastBackup).inDays >= 1) {
        if ((await repo.getSetting('auto_cloud_backup')) != '0') await uploadBackup();
      }
    } catch (_) {
      // Sin conexión o servidor caído: se reintentará la próxima vez.
    }
  }
}
