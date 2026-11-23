import 'package:flutter/material.dart';

import '../data/chains.dart';
import '../data/models.dart';
import '../main.dart' show repo;
import '../widgets.dart';
import 'settings_screen.dart';
import 'store_picker_screen.dart';
import 'store_edit_screen.dart';

/// Mantenimiento de supermercados.
class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  Future<void> _new(BuildContext context) async {
    final s = await pickStoreFromCatalog(context);
    if (s == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoreEditScreen(storeId: s.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supermercados'),
        actions: [
          IconButton(
            tooltip: 'Ajustes de comparación',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo supermercado'),
      ),
      body: RepoBuilder<List<Store>>(
        load: repo.stores,
        builder: (context, stores) {
          if (stores.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Añade tu supermercado habitual.\nCada tienda nace con 18 secciones que puedes reordenar para que la lista siga tu recorrido.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _new(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir supermercado'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: stores.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = stores[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (s.chainKey.isNotEmpty) chainName(s.chainKey),
                  if (s.address.isNotEmpty) s.address,
                  if (!s.hasLocation) 'sin ubicación: no entra en la comparación',
                  if (s.hasLocation && !s.isLinked) 'sin enlazar al catálogo',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StoreEditScreen(storeId: s.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
