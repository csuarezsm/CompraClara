import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../widgets.dart';
import 'product_edit_screen.dart';
import 'scan_screen.dart';

/// Mantenimiento de artículos.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _query = '';

  void _open(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductEditScreen(productId: id)),
    );
  }

  Future<void> _new() async {
    final name = await promptText(context,
        title: 'Nuevo artículo', hint: 'Leche entera', okLabel: 'Crear');
    if (name == null) return;
    final p = await repo.createProduct(name: name);
    if (mounted) _open(p.id);
  }

  Future<void> _scan() async {
    final p = await scanProduct(context);
    if (p != null && mounted) _open(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artículos'),
        actions: [
          IconButton(
            tooltip: 'Escanear código de barras',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo artículo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre o marca',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: RepoBuilder<List<Product>>(
              load: () => repo.products(query: _query),
              builder: (context, products) {
                if (products.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.isEmpty
                            ? 'El catálogo está vacío.\nLos artículos se crean al añadirlos a una lista o al escanearlos.'
                            : 'Sin resultados para «$_query».',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text([if (p.detail.isNotEmpty) p.detail, p.section].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(p.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
