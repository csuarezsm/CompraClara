import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/sections.dart';
import '../main.dart' show repo;
import '../services/off_service.dart';
import '../util.dart';
import '../widgets.dart';
import 'scan_screen.dart';

/// Alta de un artículo. No se guarda nada hasta pulsar «Guardar», y mientras
/// se escribe se avisa de artículos parecidos para no duplicarlos.
///
/// Devuelve el artículo creado, o el existente si se elige «Usar este»
/// (en ese caso, si venía un código de barras, se le asocia).
class ProductCreateScreen extends StatefulWidget {
  const ProductCreateScreen({super.key, this.initialName = '', this.ean, this.off});

  final String initialName;
  final String? ean;
  final OffProduct? off;

  @override
  State<ProductCreateScreen> createState() => _ProductCreateScreenState();
}

class _ProductCreateScreenState extends State<ProductCreateScreen> {
  late final _name = TextEditingController(text: widget.off?.name ?? widget.initialName);
  late final _brand = TextEditingController(text: widget.off?.brand ?? '');
  late final _size = TextEditingController(text: widget.off?.quantity ?? '');
  final _notes = TextEditingController();
  late String? _ean = widget.ean;
  late String _section =
      guessSection(_name.text, tags: widget.off?.categories ?? const []);
  bool _sectionTouched = false;
  bool _saving = false;
  bool _done = false;
  List<Product> _similar = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _checkSimilar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _brand.dispose();
    _size.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != (widget.off?.name ?? widget.initialName).trim() ||
      _brand.text.trim().isNotEmpty && widget.off == null ||
      _size.text.trim().isNotEmpty && widget.off == null ||
      _notes.text.trim().isNotEmpty;

  void _onName(String v) {
    if (!_sectionTouched) {
      setState(() => _section = guessSection(v, tags: widget.off?.categories ?? const []));
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _checkSimilar);
  }

  Future<void> _checkSimilar() async {
    final list = await repo.similarProducts(_name.text);
    if (mounted) setState(() => _similar = list);
  }

  /// Usar un artículo que ya existe (y asociarle el código si venía uno).
  Future<void> _useExisting(Product p) async {
    if (_ean != null) {
      final ok = await repo.addBarcode(p.id, _ean!);
      if (!ok && mounted) {
        snack(context, 'Ese código ya pertenece a otro artículo');
        return;
      }
    }
    if (mounted) {
      _done = true;
      Navigator.pop(context, p);
    }
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (v == null || !mounted) return;
    final owner = await repo.productByBarcode(v);
    if (!mounted) return;
    if (owner != null) {
      final use = await confirm(context,
          title: 'Ese código ya existe',
          message: 'Pertenece a «${owner.name}». ¿Usar ese artículo en vez de crear otro?',
          okLabel: 'Usar «${owner.name}»');
      if (use && mounted) {
        _done = true;
        Navigator.pop(context, owner);
      }
      return;
    }
    setState(() => _ean = v);
  }

  Future<void> _save() async {
    final name = cleanName(_name.text);
    if (name.isEmpty) {
      snack(context, 'Escribe el nombre del artículo');
      return;
    }
    final same = await repo.productByName(name);
    if (same != null && mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ya existe'),
          content: Text('Ya tienes «${same.name}»${same.detail.isEmpty ? '' : ' (${same.detail})'}. '
              '¿Es el mismo artículo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('No, crear otro')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'use'), child: const Text('Sí, usar ese')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'use') {
        await _useExisting(same);
        return;
      }
      if (_brand.text.trim().isEmpty && _size.text.trim().isEmpty && mounted) {
        snack(context, 'Para distinguirlos, pon la marca o el formato');
        return;
      }
    }
    setState(() => _saving = true);
    final p = await repo.createProduct(
      name: name,
      brand: _brand.text,
      size: _size.text,
      section: _section,
      notes: _notes.text,
      allergens: widget.off?.allergens.join(',') ?? '',
      nutriscore: widget.off?.nutriscore ?? '',
      labels: widget.off?.labels.join(',') ?? '',
    );
    if (_ean != null) await repo.addBarcode(p.id, _ean!);
    if (mounted) {
      _done = true;
      Navigator.pop(context, p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = parseSize(_size.text);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_dirty || _done) {
          Navigator.of(context).pop(result);
          return;
        }
        final leave = await confirm(context,
            title: 'Descartar el artículo', message: 'No se guardará nada.', okLabel: 'Descartar');
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nuevo artículo')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Guardar artículo'),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.off != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Datos de Open Food Facts para el código ${widget.ean}. Revísalos antes de guardar.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else if (widget.ean != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('El código ${widget.ean} no está en tu catálogo ni en Open Food Facts. '
                    'Ponle nombre (o elige un artículo que ya tengas) y se reconocerá la próxima vez.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            TextField(
              controller: _name,
              autofocus: widget.off == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Leche entera'),
              onChanged: _onName,
            ),
            if (_similar.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                color: scheme.secondaryContainer,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('¿Es alguno de estos? Así no se duplica.',
                        style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
                  ),
                  for (final p in _similar)
                    ListTile(
                      dense: true,
                      title: Text(p.name, style: TextStyle(color: scheme.onSecondaryContainer)),
                      subtitle: Text([if (p.detail.isNotEmpty) p.detail, p.section].join(' · '),
                          style: TextStyle(color: scheme.onSecondaryContainer)),
                      trailing: TextButton(onPressed: () => _useExisting(p), child: const Text('Usar este')),
                    ),
                ]),
              ),
            TextField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Marca', hintText: 'Opcional'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _size,
              decoration: InputDecoration(
                labelText: 'Formato',
                hintText: '1 L, 500 g, 6 x 1,5 L…',
                helperText: unit == null
                    ? 'Con el formato se calcula el precio por kg o litro'
                    : 'Se comparará por precio por ${unit.unit}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SectionDropdown(
              value: _section,
              label: 'Sección del súper',
              onChanged: (v) => setState(() {
                _section = v;
                _sectionTouched = true;
              }),
            ),
            if (!_sectionTouched)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Propuesta según el nombre; cámbiala si no es correcta.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.qr_code),
              title: Text(_ean ?? 'Sin código de barras'),
              subtitle: const Text('Opcional: para reconocerlo al escanear y compartir precios'),
              trailing: _ean == null
                  ? IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)
                  : IconButton(
                      tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _ean = null)),
            ),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notas', hintText: 'Opcional'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre el alta de artículo y devuelve el creado (o el existente elegido).
Future<Product?> createProductFlow(BuildContext context, {String initialName = '', String? ean, OffProduct? off}) =>
    Navigator.of(context).push<Product>(MaterialPageRoute(
      builder: (_) => ProductCreateScreen(initialName: initialName, ean: ean, off: off),
    ));
