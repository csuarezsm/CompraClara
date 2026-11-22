import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../services/quick_parse.dart';
import '../services/speech_service.dart';
import '../widgets.dart';
import 'packs_screen.dart' show addPackDialog;
import 'scan_screen.dart';

/// Añadir artículos a una lista: buscar, escribir varios de corrido,
/// dictar por voz, escanear, habituales y packs.
class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key, required this.listId});

  final String listId;

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final TextEditingController _q = TextEditingController();
  String _query = '';
  bool _listening = false;

  @override
  void dispose() {
    _q.dispose();
    if (_listening) SpeechService.stop();
    super.dispose();
  }

  bool get _isMulti =>
      _query.contains(',') || _query.contains('\n') || RegExp(r'\s+y\s+').hasMatch(_query);

  Future<({List<Product> products, Set<String> inList, List<Habitual> due})> _load() async {
    final products = await repo.products(query: _isMulti ? '' : _query);
    final items = await repo.items(widget.listId);
    final inList = items.where((i) => i.status == statusPending).map((i) => i.productId).toSet();
    final due = _query.isEmpty
        ? (await repo.habituals()).where((h) => h.isDue && !inList.contains(h.product.id)).toList()
        : <Habitual>[];
    return (products: _query.isEmpty || !_isMulti ? products : <Product>[], inList: inList, due: due);
  }

  Future<void> _add(Product p) async {
    final merged = await repo.addItem(widget.listId, p);
    if (!mounted) return;
    snack(context, merged ? 'Ya estaba: cantidad sumada' : 'Añadido: ${p.name}');
  }

  Future<void> _createAndAdd(String name) async {
    final p = await repo.createProduct(name: name);
    await repo.addItem(widget.listId, p);
    if (!mounted) return;
    _clear();
    snack(context, 'Añadido a ${p.section}: ${p.name}');
  }

  void _clear() {
    _q.clear();
    setState(() => _query = '');
  }

  /// Añade todos los artículos escritos o dictados de corrido.
  Future<void> _addMany(String text) async {
    final parsed = parseQuickItems(text);
    if (parsed.isEmpty) return;
    var created = 0;
    for (final q in parsed) {
      var p = await repo.productByName(q.name);
      if (p == null) {
        final similar = await repo.products(query: q.name);
        p = similar.isNotEmpty && similar.first.name.toLowerCase().startsWith(q.name.toLowerCase())
            ? similar.first
            : null;
      }
      if (p == null) {
        p = await repo.createProduct(name: q.name);
        created++;
      }
      await repo.addItem(widget.listId, p, qty: q.qty, note: q.unit, notify: false);
    }
    repo.refresh();
    if (!mounted) return;
    _clear();
    snack(context,
        'Añadidos ${parsed.length} artículos${created > 0 ? ' ($created nuevos en el catálogo)' : ''}');
  }

  Future<void> _voice() async {
    if (_listening) {
      await SpeechService.stop();
      setState(() => _listening = false);
      return;
    }
    var heard = '';
    final ok = await SpeechService.listen(
      onText: (t) {
        heard = t;
        if (mounted) setState(() => _q.text = t);
      },
      onDone: () async {
        if (!mounted || !_listening) return;
        setState(() => _listening = false);
        if (heard.trim().isNotEmpty) await _addMany(heard);
      },
    );
    if (!mounted) return;
    if (!ok) {
      snack(context, 'El reconocimiento de voz no está disponible. Revisa el permiso de micrófono.');
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _scan() async {
    final p = await scanProduct(context);
    if (p == null || !mounted) return;
    await _add(p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Buscar, o «leche, 2 kg papas, huevos»',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (v) {
            if (_isMulti) _addMany(v);
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(icon: const Icon(Icons.close), onPressed: _clear),
          IconButton(
            tooltip: 'Dictar',
            icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                color: _listening ? Theme.of(context).colorScheme.error : null),
            onPressed: _voice,
          ),
          IconButton(
            tooltip: 'Escanear código de barras',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
        ],
      ),
      body: RepoBuilder<({List<Product> products, Set<String> inList, List<Habitual> due})>(
        load: _load,
        builder: (context, data) {
          final q = _query.trim();
          final exact = data.products.any((p) => p.name.toLowerCase() == q.toLowerCase());
          final parsed = _isMulti ? parseQuickItems(q) : const <QuickItem>[];
          return ListView(
            children: [
              if (_listening)
                const ListTile(
                  leading: Icon(Icons.graphic_eq),
                  title: Text('Escuchando…'),
                  subtitle: Text('Di por ejemplo: «dos kilos de papas, leche y una docena de huevos»'),
                ),
              if (_isMulti && parsed.isNotEmpty) ...[
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.playlist_add)),
                  title: Text('Añadir ${parsed.length} artículos'),
                  subtitle: Text(parsed
                      .map((e) => '${e.name}${e.qty != 1 ? ' x${e.qty == e.qty.roundToDouble() ? e.qty.toInt() : e.qty}' : ''}'
                          '${e.unit.isNotEmpty ? ' ${e.unit}' : ''}')
                      .join(', ')),
                  onTap: () => _addMany(q),
                ),
              ] else if (q.isNotEmpty && !exact)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.add)),
                  title: Text('Crear «$q» y añadir'),
                  subtitle: const Text('Se guarda en el catálogo con su sección'),
                  onTap: () => _createAndAdd(q),
                ),
              if (q.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(spacing: 8, children: [
                    ActionChip(
                      avatar: const Icon(Icons.inventory_outlined, size: 18),
                      label: const Text('Añadir un pack'),
                      onPressed: () => addPackDialog(context, widget.listId),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Pegar lista'),
                      onPressed: () async {
                        final t = await promptText(context,
                            title: 'Pegar lista o receta',
                            hint: 'Un artículo por línea o separados por comas',
                            okLabel: 'Añadir',
                            maxLines: 8);
                        if (t != null) await _addMany(t);
                      },
                    ),
                  ]),
                ),
              if (data.due.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('Te toca comprar',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        for (final h in data.due) {
                          await repo.addItem(widget.listId, h.product, notify: false);
                        }
                        repo.refresh();
                        if (context.mounted) snack(context, 'Añadidos ${data.due.length} habituales');
                      },
                      child: const Text('Añadir todos'),
                    ),
                  ]),
                ),
                for (final h in data.due)
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(h.product.name),
                    subtitle: Text('Lo compras cada ${h.everyDays!.round()} días · última hace ${h.daysSince}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _add(h.product),
                  ),
                const Divider(),
              ],
              if (data.products.isEmpty && q.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Tu catálogo está vacío.\nEscribe un artículo para crearlo, dicta varios o escanea su código.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (!_isMulti)
                for (final p in data.products)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text([if (p.detail.isNotEmpty) p.detail, p.section].join(' · ')),
                    trailing: data.inList.contains(p.id)
                        ? const Chip(label: Text('En la lista'))
                        : const Icon(Icons.add_circle_outline),
                    onTap: () => _add(p),
                  ),
            ],
          );
        },
      ),
    );
  }
}
