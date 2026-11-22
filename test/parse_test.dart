import 'package:compraclara/services/ocr_service.dart';
import 'package:compraclara/services/quick_parse.dart';
import 'package:compraclara/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Texto de corrido', () {
    test('varios artículos con cantidades', () {
      final r = parseQuickItems('2 kg de papas, una docena de huevos y leche x6');
      expect(r.length, 3);
      expect(r[0].name, 'Papas');
      expect(r[0].qty, 2);
      expect(r[0].unit, 'kg');
      expect(r[1].name, 'Huevos');
      expect(r[1].qty, 12);
      expect(r[2].name, 'Leche');
      expect(r[2].qty, 6);
    });

    test('dictado sin comas y media docena', () {
      final r = parseQuickItems('media docena de yogures y tres latas de atún');
      expect(r.map((e) => e.name).toList(), ['Yogures', 'Atún']);
      expect(r[0].qty, 6);
      expect(r[1].qty, 3);
    });

    test('lista pegada por líneas', () {
      final r = parseQuickItems('Pan\nTomates\n\n  Aceite de oliva ');
      expect(r.map((e) => e.name).toList(), ['Pan', 'Tomates', 'Aceite de oliva']);
    });
  });

  group('Formato a unidad base', () {
    test('litros, gramos y packs', () {
      expect(parseSize('1 L')!.qty, 1);
      expect(parseSize('500 g')!.unit, 'kg');
      expect(parseSize('500 g')!.qty, 0.5);
      expect(parseSize('6 x 1,5 L')!.qty, 9);
      expect(parseSize('750 ml')!.qty, 0.75);
      expect(parseSize('12 ud')!.unit, 'ud');
      expect(parseSize(''), isNull);
    });
  });

  group('Ticket', () {
    test('líneas, cantidades, total y fecha', () {
      final rows = [
        'SUPERMERCADO EJEMPLO S.A.',
        'C/ Real 1 Arrecife  NIF B00000000',
        '21/11/2026 18:32',
        'LECHE ENTERA 1L   0,95',
        '2 x 0,65   1,30',
        'PAN BARRA',
        'TOMATE RAMA   2,10',
        '3 YOGUR NATURAL   1,50',
        'TOTAL   5,85',
        'TARJETA   5,85',
        'IVA 7%   0,38',
      ];
      final s = OcrService.parseTicketRows(rows, rows.join('\n'));
      expect(s.date, '2026-11-21');
      expect(s.total, 5.85);
      expect(s.storeHint, contains('SUPERMERCADO'));
      expect(s.lines.map((l) => l.raw).toList(), ['LECHE ENTERA 1L', 'PAN BARRA', 'TOMATE RAMA', 'YOGUR NATURAL']);
      expect(s.lines[0].amount, 0.95);
      expect(s.lines[1].qty, 2);
      expect(s.lines[1].unitPrice, 0.65);
      expect(s.lines[1].amount, 1.30);
      expect(s.lines[3].qty, 3);
      expect(s.lines[3].unitPrice, closeTo(0.5, 0.001));
      final sum = s.lines.fold<double>(0, (a, l) => a + (l.amount ?? 0));
      expect(sum, closeTo(s.total!, 0.001));
    });
  });

  test('distancia Arrecife - Las Palmas', () {
    expect(distanceKm(28.963, -13.55, 28.1235, -15.4363), greaterThan(150));
  });
}
