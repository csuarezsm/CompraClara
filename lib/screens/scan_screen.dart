import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../services/off_service.dart';
import '../widgets.dart';
import 'product_create_screen.dart';

/// Pantalla de cámara: devuelve el código leído (o escrito a mano).
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.allFormats = false});

  /// true para tarjetas de fidelidad (Code 128, QR…); false solo productos.
  final bool allFormats;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: widget.allFormats
        ? const [BarcodeFormat.all]
        : const [
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  Future<void> _manual() async {
    final v = await promptText(context,
        title: 'Escribir código de barras', hint: 'Por ejemplo 8410000000000', okLabel: 'Buscar');
    if (v != null && mounted) {
      _done = true;
      Navigator.of(context).pop(v.replaceAll(RegExp(r'\s'), ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear código'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Escribir el código',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: _manual,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 290,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: Text(
              'Apunta al código de barras del producto',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre la cámara y devuelve el artículo (existente o recién creado).
Future<Product?> scanProduct(BuildContext context) async {
  final ean = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const ScanScreen()),
  );
  if (ean == null || !context.mounted) return null;
  return resolveBarcode(context, ean);
}

/// Busca el código en el catálogo propio y, si no está, en Open Food Facts.
Future<Product?> resolveBarcode(BuildContext context, String ean) async {
  final known = await repo.productByBarcode(ean);
  if (known != null) return known;
  if (!context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  OffProduct? off;
  try {
    off = await OffService.lookup(ean);
  } catch (_) {
    off = null;
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();
  return createProductFlow(context, ean: ean, off: off);
}
