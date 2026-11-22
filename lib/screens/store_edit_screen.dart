import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart' show repo;
import '../widgets.dart';

/// Ficha del supermercado: secciones (orden del recorrido) y artículos por sección.
class StoreEditScreen extends StatelessWidget {
  const StoreEditScreen({super.key, required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<Store?>(
      load: () => repo.storeById(storeId),
      builder: (context, store) {
        if (store == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Supermercado no encontrado')));
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(store.name),
              actions: [
                IconButton(
                  tooltip: 'Renombrar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final n = await promptText(context, title: 'Renombrar supermercado', initial: store.name);
                    if (n != null) await repo.renameStore(store.id, n);
                  },
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Eliminar «${store.name}»',
                      message: 'Se borrarán sus secciones y los precios guardados en esta tienda.',
                      okLabel: 'Eliminar',
                    );
                    if (ok) {
                      await repo.deleteStore(store.id);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                ),
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Secciones'),
                Tab(text: 'Artículos'),
              ]),
            ),
            body: TabBarView(
              children: [
                _SectionsTab(storeId: store.id),
                _ProductsTab(storeId: store.id),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionsTab extends StatelessWidget {
  const _SectionsTab({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<List<StoreSection>>(
      load: () => repo.sections(storeId),
      builder: (context, sections) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Arrastra para ordenar según el recorrido real de la tienda. '
                'La lista y el modo compra seguirán este orden.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: sections.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final ids = sections.map((s) => s.id).toList();
                  final moved = ids.removeAt(oldIndex);
                  ids.insert(newIndex, moved);
                  repo.reorderSections(ids);
                },
                itemBuilder: (context, i) {
                  final s = sections[i];
                  return ListTile(
                    key: ValueKey(s.id),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(
                      s.name,
                      style: TextStyle(
                        color: s.hidden ? Theme.of(context).disabledColor : null,
                      ),
                    ),
                    subtitle: s.hidden ? const Text('Oculta') : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'rename') {
                          final n = await promptText(context, title: 'Renombrar sección', initial: s.name);
                          if (n != null) await repo.renameSection(s.id, n);
                        } else if (a == 'hide') {
                          await repo.setSectionHidden(s.id, !s.hidden);
                        } else if (a == 'delete') {
                          final ok = await confirm(
                            context,
                            title: 'Eliminar «${s.name}»',
                            message: 'Sus artículos pasarán a «Otros» en esta tienda.',
                            okLabel: 'Eliminar',
                          );
                          if (ok) await repo.deleteSection(s.id);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                        PopupMenuItem(value: 'hide', child: Text(s.hidden ? 'Mostrar' : 'Ocultar')),
                        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final n = await promptText(context,
                              title: 'Nueva sección', hint: 'Platos preparados', okLabel: 'Añadir');
                          if (n != null) await repo.addSection(storeId, n);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir sección'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final n = await repo.applyTemplate(storeId);
                          if (context.mounted) {
                            snack(context, n == 0 ? 'Ya tiene todas las secciones' : 'Añadidas $n secciones');
                          }
                        },
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Aplicar plantilla'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductsData {
  _ProductsData(this.products, this.sections, this.overrides);

  final List<Product> products;
  final List<StoreSection> sections;
  final Map<String, String> overrides;
}

class _ProductsTab extends StatefulWidget {
  const _ProductsTab({required this.storeId});

  final String storeId;

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  String _query = '';

  Future<_ProductsData> _load() async => _ProductsData(
        await repo.products(query: _query),
        await repo.sections(widget.storeId),
        await repo.locationsInStore(widget.storeId),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar artículo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: RepoBuilder<_ProductsData>(
            load: _load,
            builder: (context, d) {
              if (d.products.isEmpty) {
                return const Center(child: Text('No hay artículos en el catálogo'));
              }
              return ListView.separated(
                itemCount: d.products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = d.products[i];
                  final resolved =
                      Repo.resolveSection(p.section, p.id, d.sections, d.overrides);
                  final custom = d.overrides.containsKey(p.id);
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.detail),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Mover a otra sección',
                      onSelected: (v) =>
                          repo.setLocation(p.id, widget.storeId, v == '_auto' ? null : v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '_auto', child: Text('Automático')),
                        for (final s in d.sections)
                          PopupMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            resolved?.name ?? 'Sin sección',
                            style: TextStyle(
                              fontWeight: custom ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
