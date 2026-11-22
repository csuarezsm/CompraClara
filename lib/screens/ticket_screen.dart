import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../services/ocr_service.dart';
import '../util.dart';
import '../widgets.dart';
import 'list_detail_screen.dart' show chooseStore;
import 'purchases_screen.dart';

/// Línea editable de la revisión del ticket.
class _Line {
  _Line({required this.raw, required this.qty, required this.amount, this.unitPrice, this.product});

  String raw;
  double qty;
  double? amount;
  double? unitPrice;
  Product? product;

  /// Aviso del modo caja (no estaba en la lista, precio distinto…).
  String? warning;
}

/// Lee un ticket con la cámara y, tras revisarlo, guarda la compra y los precios.
/// Con [listId] compara además con lo cogido en la lista (modo caja).
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, this.listId, this.storeId});

  final String? listId;
  final String? storeId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  bool _busy = false;
  String? _imagePath;
  Store? _store;
  String _date = todayIso();
  double? _total;
  List<_Line> _lines = [];
  List<ListItem> _picked = [];
  bool _read = false;

  @override
  void initState() {
    super.initState();
    _initStore();
  }

  Future<void> _initStore() async {
    final s = await repo.storeById(widget.storeId);
    if (widget.listId != null) {
      _picked = (await repo.items(widget.listId!)).where((i) => i.status == statusPicked).toList();
    }
    if (mounted) setState(() => _store = s);
  }

  Future<void> _capture(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, imageQuality: 90, maxWidth: 2400);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tickets = Directory('${dir.path}/tickets');
      if (!tickets.existsSync()) tickets.createSync(recursive: true);
      final dest = '${tickets.path}/ticket_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(x.path).copy(dest);
      _imagePath = dest;
      final scan = await OcrService.readTicket(dest);
      await _apply(scan);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo leer el ticket: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(TicketScan scan) async {
    final products = await repo.products();
    _store ??= await _guessStore(scan.storeHint);
    final key = _store?.id ?? scan.storeHint.toLowerCase();
    final lines = <_Line>[];
    for (final l in scan.lines) {
      Product? p;
      final aliasId = await repo.aliasLookup(key, l.raw);
      if (aliasId != null) p = await repo.productById(aliasId);
      p ??= _fuzzy(l.raw, products);
      lines.add(_Line(raw: l.raw, qty: l.qty, amount: l.amount, unitPrice: l.unitPrice, product: p));
    }
    setState(() {
      _lines = lines;
      _total = scan.total;
      _date = scan.date ?? _date;
      _read = true;
    });
    _checkout();
  }

  Future<Store?> _guessStore(String hint) async {
    if (hint.isEmpty) return null;
    final h = hint.toLowerCase();
    for (final s in await repo.stores()) {
      final first = s.name.toLowerCase().split(' ').first;
      if (first.length >= 3 && h.contains(first)) return s;
    }
    return null;
  }

  /// Emparejamiento aproximado por palabras en común con el nombre del artículo.
  static Product? _fuzzy(String raw, List<Product> products) {
    final words = normalizeTicketText(raw).split(' ').where((w) => w.length >= 3).toSet();
    if (words.isEmpty) return null;
    Product? best;
    var bestScore = 0.0;
    for (final p in products) {
      final pw = normalizeTicketText('${p.name} ${p.brand}').split(' ').where((w) => w.length >= 3).toSet();
      if (pw.isEmpty) continue;
      var hits = 0;
      for (final w in words) {
        if (pw.any((x) => x.startsWith(w) || w.startsWith(x))) hits++;
      }
      final score = hits / words.length;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  /// Modo caja: compara lo cobrado con lo cogido.
  void _checkout() {
    if (_picked.isEmpty) return;
    final byProduct = {for (final i in _picked) i.productId: i};
    for (final l in _lines) {
      final p = l.product;
      if (p == null) continue;
      final it = byProduct[p.id];
      if (it == null) {
        l.warning = 'No estaba entre lo cogido';
      } else if (it.price != null && l.unitPrice != null && (l.unitPrice! - it.price!).abs() > 0.009) {
        l.warning = 'En la etiqueta ponía ${money(it.price)}';
      } else if (_lines.where((x) => x.product?.id == p.id).length > 1) {
        l.warning = 'Aparece repetido en el ticket';
      }
    }
    setState(() {});
  }

  double get _sum => _lines.fold(0, (a, l) => a + (l.amount ?? 0));

  Future<void> _pickProduct(_Line l) async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(initial: l.raw),
    );
    if (p != null) {
      setState(() => l.product = p);
      _checkout();
    }
  }

  Future<void> _editLine(_Line l) async {
    final name = TextEditingController(text: l.raw);
    final qty = TextEditingController(text: qtyText(l.qty));
    final amount = TextEditingController(text: l.amount == null ? '' : l.amount!.toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Línea del ticket'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Texto')),
          TextField(
            controller: qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cantidad'),
          ),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Importe', suffixText: '€'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      l.raw = name.text.trim();
      l.qty = parseNum(qty.text) ?? 1;
      l.amount = parseNum(amount.text);
      l.unitPrice = l.amount == null || l.qty == 0 ? null : l.amount! / l.qty;
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return;
    final unlinked = _lines.where((l) => l.product == null).length;
    if (unlinked > 0) {
      final ok = await confirm(context,
          title: 'Hay $unlinked línea(s) sin artículo',
          message: 'Se guardarán en la compra pero sin precio en el catálogo. '
              'Puedes enlazarlas tocando cada una, o crear los artículos automáticamente.',
          okLabel: 'Crear artículos y guardar');
      if (!ok) return;
      for (final l in _lines.where((l) => l.product == null)) {
        final name = l.raw.isEmpty ? 'Artículo' : l.raw[0].toUpperCase() + l.raw.substring(1).toLowerCase();
        l.product = await repo.productByName(name) ?? await repo.createProduct(name: name);
      }
    }
    final total = _total ?? _sum;
    final id = await repo.saveTicketPurchase(
      storeId: _store?.id,
      storeName: _store?.name ?? 'Ticket',
      date: _date,
      total: double.parse(total.toStringAsFixed(2)),
      lines: [
        for (final l in _lines)
          (
            productId: l.product?.id,
            raw: l.raw,
            qty: l.qty,
            unitPrice: l.unitPrice == null ? null : double.parse(l.unitPrice!.toStringAsFixed(2)),
            amount: l.amount,
          )
      ],
      imagePath: _imagePath,
    );
    if (widget.listId != null) {
      final left = await repo.removePicked(widget.listId!);
      if (left == 0) await repo.setListArchived(widget.listId!, true);
    }
    if (!mounted) return;
    snack(context, _store == null
        ? 'Compra guardada (sin tienda: los precios no se registran)'
        : 'Compra guardada y precios actualizados en ${_store!.name}');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diff = _total == null ? null : _sum - _total!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.listId == null ? 'Leer ticket' : 'Repasar ticket')),
      bottomNavigationBar: !_read
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _lines.isEmpty ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar compra'),
                ),
              ),
            ),
      body: _busy
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Leyendo el ticket…'),
              ]),
            )
          : !_read
              ? _intro()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storefront),
                      title: Text(_store?.name ?? 'Elegir supermercado'),
                      subtitle: const Text('Necesario para guardar los precios'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final s = await chooseStore(context, currentId: _store?.id, forShopping: true);
                        if (s != null && s.id != '_none') setState(() => _store = s);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.event),
                      title: Text('Fecha: ${dateEs(_date)}'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _date = isoDate(d));
                      },
                    ),
                    ListTile(
                      leading: Icon(diff == null || diff.abs() < 0.02 ? Icons.check_circle_outline : Icons.warning_amber),
                      title: Text('Suma de líneas: ${money(_sum)}'),
                      subtitle: Text(_total == null
                          ? 'No se encontró el TOTAL en el ticket'
                          : (diff!.abs() < 0.02
                              ? 'Cuadra con el total del ticket (${money(_total)})'
                              : 'No cuadra con el total del ticket (${money(_total)}): revisa las líneas')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final v = await promptText(context,
                            title: 'Total del ticket',
                            initial: _total == null ? '' : _total!.toStringAsFixed(2).replaceAll('.', ','));
                        if (v != null) setState(() => _total = parseNum(v));
                      },
                    ),
                    if (_picked.isNotEmpty) _cashierSummary(),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text('Toca una línea para enlazarla con un artículo; mantén pulsado para corregirla.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    for (var i = 0; i < _lines.length; i++)
                      Dismissible(
                        key: ObjectKey(_lines[i]),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => setState(() => _lines.removeAt(i)),
                        child: ListTile(
                          leading: Icon(
                            _lines[i].warning != null
                                ? Icons.error_outline
                                : (_lines[i].product == null ? Icons.link_off : Icons.link),
                            color: _lines[i].warning != null
                                ? Theme.of(context).colorScheme.error
                                : (_lines[i].product == null ? Colors.orange : Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(_lines[i].product?.name ?? _lines[i].raw),
                          subtitle: Text([
                            if (_lines[i].product != null) _lines[i].raw,
                            if (_lines[i].product == null) 'Sin enlazar: toca para elegir artículo',
                            if (_lines[i].qty != 1) '${qtyText(_lines[i].qty)} x ${money(_lines[i].unitPrice)}',
                            if (_lines[i].warning != null) _lines[i].warning!,
                          ].join(' · ')),
                          trailing: Text(money(_lines[i].amount)),
                          onTap: () => _pickProduct(_lines[i]),
                          onLongPress: () => _editLine(_lines[i]),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () {
                        final l = _Line(raw: '', qty: 1, amount: null);
                        setState(() => _lines.add(l));
                        _editLine(l);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir línea'),
                    ),
                  ],
                ),
    );
  }

  Widget _cashierSummary() {
    final charged = _lines.map((l) => l.product?.id).whereType<String>().toSet();
    final notCharged = _picked.where((i) => !charged.contains(i.productId)).toList();
    final warnings = _lines.where((l) => l.warning != null).length;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Repaso de caja', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(warnings == 0 ? 'Sin diferencias en lo cobrado.' : '$warnings línea(s) a revisar (marcadas en rojo).'),
          if (notCharged.isNotEmpty)
            Text('Cogido pero no aparece en el ticket: ${notCharged.map((e) => e.name).join(', ')}'),
        ]),
      ),
    );
  }

  Widget _intro() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Haz una foto del ticket entero, plano y con buena luz. '
              'La lectura se hace en el móvil, sin enviar la foto a ningún sitio.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
              onPressed: () => _capture(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Hacer foto'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _capture(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir de la galería'),
            ),
          ]),
        ),
      );
}

/// Buscador de artículos para enlazar una línea (o crear uno nuevo).
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.initial});

  final String initial;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final TextEditingController _q = TextEditingController(
      text: widget.initial.isEmpty ? '' : widget.initial.split(' ').first.toLowerCase());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar artículo'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: repo.products(query: _q.text),
            builder: (context, snap) {
              final ps = snap.data ?? const <Product>[];
              return ListView(children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text('Crear «${_q.text.trim().isEmpty ? widget.initial : _q.text.trim()}»'),
                  onTap: () async {
                    final raw = _q.text.trim().isEmpty ? widget.initial : _q.text.trim();
                    final name = raw.isEmpty ? 'Artículo' : raw[0].toUpperCase() + raw.substring(1).toLowerCase();
                    final p = await repo.createProduct(name: name);
                    if (context.mounted) Navigator.pop(context, p);
                  },
                ),
                for (final p in ps)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.detail),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
