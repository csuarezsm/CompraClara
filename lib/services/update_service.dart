import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show repo;

/// Versión publicada en GitHub Releases.
class AppRelease {
  AppRelease({required this.version, required this.build, required this.notes, required this.apkUrl, required this.pageUrl});

  final String version;
  final int build;
  final String notes;
  final String? apkUrl;
  final String pageUrl;
}

/// Busca versiones nuevas en GitHub Releases (repositorio público).
/// Las etiquetas son `v<versión>-<compilación>`, p. ej. `v0.4.2-19`; la compilación
/// coincide con el `buildNumber` de la app, así que basta con compararlo.
class UpdateService {
  static const repoPath = 'csuarezsm/CompraClara';

  static Future<AppRelease?> latest() async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repoPath/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'CompraClara'},
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map) return null;
    final tag = (j['tag_name'] as String?) ?? '';
    final m = RegExp(r'^v?([\d.]+)-(\d+)$').firstMatch(tag);
    if (m == null) return null;
    String? apk;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] as String? ?? '').endsWith('.apk')) {
        apk = a['browser_download_url'] as String?;
        break;
      }
    }
    return AppRelease(
      version: m.group(1)!,
      build: int.parse(m.group(2)!),
      notes: ((j['body'] as String?) ?? '').trim(),
      apkUrl: apk,
      pageUrl: (j['html_url'] as String?) ?? 'https://github.com/$repoPath/releases/latest',
    );
  }

  /// Devuelve la versión nueva si la hay (null si ya está al día o no se puede consultar).
  static Future<AppRelease?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      final rel = await latest();
      if (rel == null || rel.build <= current) return null;
      return rel;
    } catch (_) {
      return null;
    }
  }

  /// Al abrir la app: como mucho una vez al día y sin repetir una versión que se pospuso.
  static Future<void> checkOnStart(BuildContext context) async {
    final last = DateTime.tryParse(await repo.getSetting('update_checked') ?? '');
    if (last != null && DateTime.now().difference(last).inHours < 20) return;
    await repo.setSetting('update_checked', DateTime.now().toIso8601String());
    final rel = await check();
    if (rel == null || !context.mounted) return;
    if (await repo.getSetting('update_skipped') == '${rel.build}') return;
    if (!context.mounted) return;
    await showUpdateDialog(context, rel);
  }

  /// Comprobación manual (Ajustes → Acerca de).
  static Future<void> checkNow(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    m.showSnackBar(const SnackBar(content: Text('Buscando actualizaciones…')));
    final rel = await check();
    if (!context.mounted) return;
    m.hideCurrentSnackBar();
    if (rel == null) {
      final info = await PackageInfo.fromPlatform();
      m.showSnackBar(SnackBar(content: Text('Tienes la última versión (${info.version}).')));
      return;
    }
    await showUpdateDialog(context, rel);
  }

  static Future<void> showUpdateDialog(BuildContext context, AppRelease rel) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: Text('Nueva versión ${rel.version}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tienes la ${info.version}. Se descargará el instalador; ábrelo al terminar y pulsa «Actualizar». '
                'Tus datos se conservan.'),
            if (rel.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(rel.notes, style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Omitir esta')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'later'), child: const Text('Más tarde')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'update'), child: const Text('Actualizar')),
        ],
      ),
    );
    if (action == 'skip') {
      await repo.setSetting('update_skipped', '${rel.build}');
    } else if (action == 'update') {
      await launchUrl(Uri.parse(rel.apkUrl ?? rel.pageUrl), mode: LaunchMode.externalApplication);
    }
  }
}
