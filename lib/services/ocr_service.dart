import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Línea leída de un ticket.
class TicketLine {
  TicketLine({required this.raw, this.qty = 1, this.unitPrice, this.amount});

  String raw;
  double qty;
  double? unitPrice;
  double? amount;
}

class TicketScan {
  TicketScan({
    required this.storeHint,
    required this.date,
    required this.total,
    required this.lines,
    required this.fullText,
  });

  final String storeHint;
  final String? date; // yyyy-mm-dd
  final double? total;
  final List<TicketLine> lines;
  final String fullText;
}

class LabelScan {
  LabelScan({required this.name, required this.price, required this.unitPrice, required this.unit, required this.offer});

  final String name;
  final double? price;
  final double? unitPrice;
  final String unit;
  final bool offer;
}

/// Reconocimiento de texto en el propio móvil (ML Kit, sin conexión).
class OcrService {
  static final _price = RegExp(r'(-?\d{1,4}[.,]\d{2})(?!\d)');
  static final _skip = RegExp(
      r'total|subtotal|iva|i\.v\.a|base imp|cuota|entregado|cambio|efectivo|tarjeta|visa|mastercard|'
      r'n\.?i\.?f|c\.?i\.?f|tel[eé]?f|factura|ticket|caja|cajer|operaci|autoriz|importe a pagar|a pagar|'
      r'pago|devoluci[oó]n de|gracias|horario|www\.|@|ahorro total|puntos|saldo',
      caseSensitive: false);

  static double? _num(String s) => double.tryParse(s.replaceAll(',', '.'));

  /// Agrupa los fragmentos reconocidos en renglones según su altura en la foto.
  static List<String> _rows(RecognizedText text) {
    final lines = <TextLine>[for (final b in text.blocks) ...b.lines];
    lines.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final rows = <List<TextLine>>[];
    for (final l in lines) {
      final h = max(8.0, l.boundingBox.height);
      if (rows.isNotEmpty) {
        final last = rows.last;
        final cy = last.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / last.length;
        if ((l.boundingBox.center.dy - cy).abs() < h * 0.55) {
          last.add(l);
          continue;
        }
      }
      rows.add([l]);
    }
    return rows.map((r) {
      r.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      return r.map((e) => e.text.trim()).join('  ');
    }).toList();
  }

  static Future<RecognizedText> _recognize(String imagePath) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return await rec.processImage(InputImage.fromFilePath(imagePath));
    } finally {
      await rec.close();
    }
  }

  static String? _date(String text) {
    final m = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})').firstMatch(text);
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 2000 || y > 2100) return null;
    return '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static Future<TicketScan> readTicket(String imagePath) async {
    final text = await _recognize(imagePath);
    return parseTicketRows(_rows(text), text.text);
  }

  /// Interpreta los renglones de un ticket (separado para poder probarlo).
  static TicketScan parseTicketRows(List<String> rows, String fullText) {
    String storeHint = '';
    for (final r in rows.take(4)) {
      final letters = r.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ ]'), '').trim();
      if (letters.length >= 4) {
        storeHint = letters;
        break;
      }
    }
    double? total;
    final lines = <TicketLine>[];
    String? pendingName; // renglón con nombre pero sin precio (el precio viene debajo)
    var started = false;
    for (final row in rows) {
      final prices = _price.allMatches(row).toList();
      final lower = row.toLowerCase();
      if (prices.isEmpty) {
        final letters = row.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ]'), '');
        pendingName = started && letters.length >= 3 && !_skip.hasMatch(row) ? row.trim() : null;
        continue;
      }
      if (lower.contains('total') && !lower.contains('subtotal') && prices.isNotEmpty) {
        total ??= _num(prices.last.group(1)!);
        continue;
      }
      if (prices.isEmpty || _skip.hasMatch(row)) continue;

      // "2 x 0,95   1,90" o "0,535 kg x 2,99 €/kg  1,60": detalle de la línea anterior.
      final detail = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(?:kg|uds?|u)?\s*[x×*]\s*(\d+[.,]\d{2})',
              caseSensitive: false)
          .firstMatch(row);
      if (detail != null) {
        final q = _num(detail.group(1)!) ?? 1;
        final up = _num(detail.group(2)!);
        final amount = _num(prices.last.group(1)!);
        final namePart = row.substring(detail.end).replaceAll(_price, '').replaceAll(RegExp(r'[€/a-z]+$', caseSensitive: false), '').trim();
        if (namePart.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ]'), '').length >= 3) {
          lines.add(TicketLine(raw: namePart, qty: q, unitPrice: up, amount: amount));
        } else if (pendingName != null) {
          lines.add(TicketLine(raw: pendingName, qty: q, unitPrice: up, amount: amount));
        } else if (lines.isNotEmpty) {
          lines.last
            ..qty = q
            ..unitPrice = up
            ..amount = amount ?? lines.last.amount;
        }
        pendingName = null;
        continue;
      }
      pendingName = null;

      final amount = _num(prices.last.group(1)!);
      var name = row.substring(0, prices.last.start).replaceAll(_price, ' ');
      name = name.replaceAll(RegExp(r'[€*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      var qty = 1.0;
      final lead = RegExp(r'^(\d{1,2})\s+(?=[A-Za-zÁÉÍÓÚÑ])').firstMatch(name);
      if (lead != null) {
        qty = double.parse(lead.group(1)!);
        name = name.substring(lead.end).trim();
      }
      if (name.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ]'), '').length < 3) continue;
      started = true;
      lines.add(TicketLine(
        raw: name,
        qty: qty,
        amount: amount,
        unitPrice: amount == null ? null : amount / qty,
      ));
    }
    for (final l in lines) {
      if (l.unitPrice == null && l.amount != null && l.qty > 0) l.unitPrice = l.amount! / l.qty;
    }
    return TicketScan(
      storeHint: storeHint,
      date: _date(fullText),
      total: total,
      lines: lines,
      fullText: fullText,
    );
  }

  /// Etiqueta de estantería: el precio más grande es el de venta; el que va con
  /// "/kg" o "/l" es el precio por unidad.
  static Future<LabelScan> readLabel(String imagePath) async {
    final text = await _recognize(imagePath);
    double? bestPrice;
    var bestHeight = 0.0;
    double? unitPrice;
    var unit = '';
    var name = '';
    final full = text.text;
    final perUnit = RegExp(r'(\d{1,4}[.,]\d{2})\s*€?\s*/\s*(kg|kilo|l|lt|litro|ud|unidad)', caseSensitive: false)
        .firstMatch(full);
    if (perUnit != null) {
      unitPrice = _num(perUnit.group(1)!);
      final u = perUnit.group(2)!.toLowerCase();
      unit = u.startsWith('k') ? 'kg' : (u.startsWith('l') ? 'l' : 'ud');
    }
    for (final b in text.blocks) {
      for (final l in b.lines) {
        final t = l.text.trim();
        if (perUnit != null && t.contains(perUnit.group(1)!) && t.contains('/')) continue;
        final m = _price.firstMatch(t) ?? RegExp(r'^(\d{1,3})\s*[,.]?\s*(\d{2})\s*€?$').firstMatch(t);
        if (m != null) {
          final v = m.groupCount >= 2 && m.group(2) != null && !t.contains(',') && !t.contains('.')
              ? _num('${m.group(1)}.${m.group(2)}')
              : _num(m.group(1)!);
          if (v != null && v > 0 && l.boundingBox.height > bestHeight) {
            bestHeight = l.boundingBox.height;
            bestPrice = v;
          }
        } else {
          final letters = t.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ ]'), '').trim();
          if (letters.length > name.length && letters.length >= 4) name = letters;
        }
      }
    }
    final offer = RegExp(r'oferta|promo|antes|ahora|descuento|2\s*x\s*1|-\s*\d+\s*%', caseSensitive: false)
        .hasMatch(full);
    return LabelScan(name: name, price: bestPrice, unitPrice: unitPrice, unit: unit, offer: offer);
  }
}
