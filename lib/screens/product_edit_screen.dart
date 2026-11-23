import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../util.dart';
import '../widgets.dart';
import '../data/repository.dart';
import '../services/off_service.dart';
import 'label_capture.dart';
import 'scan_screen.dart';
import 'settings_screen.dart' show allergenNames, dietNames;

class _EditData {
  _EditData({
    required this.product,
    required this.barcodes,
    required this.stores,
    required this.sections,
    required this.locations,
    required this.history,
  });

  final Product product;
  final List<String> barcodes;
  final List<Store> stores;
  final Map<String, List<StoreSection>> sections;
  final Map<String, String> locations;
  final List<PriceEntry> history;
}

class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _size = TextEditingController();
  final _notes = TextEditingController();
  String _section = 'Otros';
  bool _filled = false;
  String _orig = '';

  String get _snapshot => [_name.text.trim(), _brand.text.trim(), _size.text.trim(), _notes.text.trim(), _section].join('|');
  bool _saved = false;
  bool get _dirty => _filled && !_saved && _snapshot != _orig;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _size.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<_EditData?> _load() async {
    final p = await repo.productById(widget.productId);
    if (p == null) return null;
    final stores = await repo.stores();
    final sections = <String, List<StoreSection>>{};
    for (final s in stores) {
      sections[s.id] = await repo.sections(s.id);
    }
    return _EditData(
      product: p,
      barcodes: await repo.barcodesOf(p.id),
      stores: stores,
      sections: sections,
      locations: await repo.locationsOf(p.id),
      history: await repo.priceHistory(p.id),
    );
  }

  void _fill(Product p) {
    if (_filled) return;
    _filled = true;
    _name.text = p.name;
    _brand.text = p.brand;
    _size.text = p.size;
    _notes.text = p.notes;
    _section = p.section;
    _orig = _snapshot;
  }

  Future<void> _save(Product p) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      snack(context, 'El nombre no puede estar vacío');
      return;
    }
    final same = await repo.productByName(name);
    if (same != null && same.id != p.id && mounted) {
      final go = await confirm(context,
          title: 'Ya existe «${same.name}»',
          message: 'Hay otro artículo con el mismo nombre${same.detail.isEmpty ? '' : ' (${same.detail})'}. '
              '¿Guardar igualmente? Pon la marca o el formato para distinguirlos.',
          okLabel: 'Guardar igualmente');
      if (!go) return;
    }
    p
      ..name = name
      ..brand = _brand.text
      ..size = _size.text
      ..notes = _notes.text
      ..section = _section;
    await repo.updateProduct(p);
    _orig = _snapshot;
    _saved = true;
    if (mounted) {
      snack(context, 'Guardado');
      Navigator.of(context).pop();
    }
  }

  Future<void> _addBarcode(String productId, String ean) async {
    final ok = await repo.addBarcode(productId, ean);
    if (!ok && mounted) snack(context, 'Ese código ya pertenece a otro artículo');
  }

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<_EditData?>(
      load: _load,
      builder: (context, d) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Artículo no encontrado')));
        }
        _fill(d.product);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (!_dirty) {
              Navigator.of(context).pop();
              return;
            }
            final leave = await confirm(context,
                title: 'Hay cambios sin guardar', message: '¿Salir sin guardarlos?', okLabel: 'Salir sin guardar');
            if (leave && context.mounted) {
              _orig = _snapshot;
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
          appBar: AppBar(
            title: const Text('Artículo'),
            actions: [
              IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Eliminar «${d.product.name}»',
                    message: 'Desaparecerá del catálogo, de las listas y su historial de precios.',
                    okLabel: 'Eliminar',
                  );
                  if (ok) {
                    await repo.deleteProduct(d.product.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _save(d.product),
                icon: const Icon(Icons.check),
                label: const Text('Guardar'),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              TextField(
                controller: _size,
                decoration: const InputDecoration(labelText: 'Formato (1 L, 500 g…)'),
              ),
              const SizedBox(height: 8),
              SectionDropdown(
                value: _section,
                label: 'Sección general',
                onChanged: (v) => setState(() => _section = v),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
              const SizedBox(height: 20),
              Text('Códigos de barras', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in d.barcodes)
                    InputChip(label: Text(e), onDeleted: () => repo.removeBarcode(e)),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear'),
                    onPressed: () async {
                      final ean = await Navigator.of(context).push<String>(
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      );
                      if (ean != null) await _addBarcode(d.product.id, ean);
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Escribir'),
                    onPressed: () async {
                      final v = await promptText(context, title: 'Código de barras', okLabel: 'Añadir');
                      if (v != null) await _addBarcode(d.product.id, v.replaceAll(RegExp(r'\s'), ''));
                    },
                  ),
                ],
              ),
              if (d.stores.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Dónde está en cada supermercado', style: Theme.of(context).textTheme.titleMedium),
                const Text('Déjalo en «Automático» salvo que esté en otra sección en esa tienda.'),
                for (final s in d.stores)
                  _LocationRow(
                    store: s,
                    sections: d.sections[s.id] ?? const [],
                    current: d.locations[s.id],
                    onChanged: (secId) => repo.setLocation(d.product.id, s.id, secId),
                  ),
              ],
              const SizedBox(height: 16),
              _FoodInfo(product: d.product, barcodes: d.barcodes),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text('Historial de precios', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: () => captureLabelPrice(context, product: d.product),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Foto etiqueta'),
                ),
              ]),
              if (d.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aún no hay precios. Se guardan durante la compra, al leer un ticket o una etiqueta.'),
                ),
              for (final h in d.history.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${money(h.price)}${h.offer ? '  (oferta)' : ''}'),
                  subtitle: Text('${h.storeName} · ${dateEs(h.date)}'),
                  trailing: Builder(builder: (_) {
                    final up = Repo.unitPrice(d.product.unitQty, d.product.unit, h.price);
                    return up == null ? const SizedBox.shrink() : Text(unitPriceText(up.value, up.unit));
                  }),
                ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.store,
    required this.sections,
    required this.current,
    required this.onChanged,
  });

  final Store store;
  final List<StoreSection> sections;
  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('${store.id}-$current'),
        // ignore: deprecated_member_use
        value: sections.any((s) => s.id == current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: store.name),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Automático')),
          for (final s in sections) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Nutri-Score, alérgenos y etiquetas (de Open Food Facts) con opción de actualizar.
class _FoodInfo extends StatelessWidget {
  const _FoodInfo({required this.product, required this.barcodes});

  final Product product;
  final List<String> barcodes;

  static const _nsColors = {
    'a': Color(0xFF038141),
    'b': Color(0xFF85BB2F),
    'c': Color(0xFFFECB02),
    'd': Color(0xFFEE8100),
    'e': Color(0xFFE63E11),
  };

  @override
  Widget build(BuildContext context) {
    final allergens = product.allergens.split(',').where((e) => e.trim().isNotEmpty).toList();
    final labels = product.labels.split(',').where((e) => dietNames.containsKey(e.trim())).toList();
    final ns = product.nutriscore;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text('Información alimentaria', style: Theme.of(context).textTheme.titleMedium)),
        if (barcodes.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Actualizar'),
            onPressed: () async {
              OffProduct? off;
              try {
                off = await OffService.lookup(barcodes.first);
              } catch (_) {
                off = null;
              }
              if (off == null) {
                if (context.mounted) snack(context, 'Sin datos en Open Food Facts para este código');
                return;
              }
              await repo.setProductFoodInfo(product.id,
                  allergens: off.allergens.join(','), nutriscore: off.nutriscore, labels: off.labels.join(','));
              if (context.mounted) snack(context, 'Datos actualizados');
            },
          ),
      ]),
      if (ns.isEmpty && allergens.isEmpty && labels.isEmpty)
        Text(barcodes.isEmpty
            ? 'Añade el código de barras para traer Nutri-Score y alérgenos de Open Food Facts.'
            : 'Sin datos todavía.'),
      if (ns.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Text('Nutri-Score '),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: _nsColors[ns] ?? Colors.grey, borderRadius: BorderRadius.circular(6)),
              child: Text(ns.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ]),
        ),
      if (allergens.isNotEmpty)
        Text('Alérgenos: ${allergens.map((k) => allergenNames[k.trim()] ?? k.trim()).join(', ')}'),
      if (labels.isNotEmpty) Text('Apto: ${labels.map((k) => dietNames[k.trim()] ?? k).join(', ')}'),
    ]);
  }
}
