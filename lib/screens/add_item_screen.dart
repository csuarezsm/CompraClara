import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../widgets.dart';
import 'scan_screen.dart';

/// Añadir artículos a una lista: buscar en el catálogo, crear o escanear.
/// Se pueden añadir varios seguidos.
class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key, required this.listId});

  final String listId;

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final TextEditingController _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<({List<Product> products, Set<String> inList})> _load() async {
    final products = await repo.products(query: _query);
    final items = await repo.items(widget.listId);
    final inList = items
        .where((i) => i.status == statusPending)
        .map((i) => i.productId)
        .toSet();
    return (products: products, inList: inList);
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
    _q.clear();
    setState(() => _query = '');
    snack(context, 'Añadido a ${p.section}: ${p.name}');
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
            hintText: 'Buscar o escribir artículo',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _q.clear();
                setState(() => _query = '');
              },
            ),
          IconButton(
            tooltip: 'Escanear código de barras',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
        ],
      ),
      body: RepoBuilder<({List<Product> products, Set<String> inList})>(
        load: _load,
        builder: (context, data) {
          final q = _query.trim();
          final exact = data.products.any((p) => p.name.toLowerCase() == q.toLowerCase());
          return ListView(
            children: [
              if (q.isNotEmpty && !exact)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.add)),
                  title: Text('Crear «$q» y añadir'),
                  subtitle: const Text('Se guarda en el catálogo con su sección'),
                  onTap: () => _createAndAdd(q),
                ),
              if (data.products.isEmpty && q.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Tu catálogo está vacío.\nEscribe un artículo para crearlo o escanea su código de barras.',
                    textAlign: TextAlign.center,
                  ),
                ),
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
