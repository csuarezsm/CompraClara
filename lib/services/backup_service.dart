import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart' show repo;
import '../util.dart';

/// Copias de seguridad (JSON) y exportaciones (CSV) que se comparten como archivo:
/// a Drive, correo, WhatsApp, Descargas…
class BackupService {
  static Future<File> _writeTemp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(content, flush: true);
    return f;
  }

  static Future<void> _share(File f, String text) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text));
  }

  static Future<void> shareBackup() async {
    final data = await repo.exportAll();
    final f = await _writeTemp(
        'CompraClara-copia-${todayIso()}.json', const JsonEncoder.withIndent(' ').convert(data));
    await _share(f, 'Copia de seguridad de CompraClara');
    await repo.setSetting('last_backup', todayIso());
  }

  /// Devuelve el número de registros restaurados, o null si se canceló.
  static Future<int?> restoreFromFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return null;
    final text = await File(path).readAsString();
    final json = jsonDecode(text);
    if (json is! Map) throw const FormatException('El archivo no es una copia de CompraClara');
    return repo.importAll(Map<String, Object?>.from(json));
  }

  static Future<void> sharePurchasesCsv() async {
    final f = await _writeTemp('CompraClara-compras-${todayIso()}.csv', '﻿${await repo.purchasesCsv()}');
    await _share(f, 'Compras exportadas de CompraClara');
  }

  static Future<void> sharePricesCsv() async {
    final f = await _writeTemp('CompraClara-precios-${todayIso()}.csv', '﻿${await repo.pricesCsv()}');
    await _share(f, 'Precios exportados de CompraClara');
  }
}
