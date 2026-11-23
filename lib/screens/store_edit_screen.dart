import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart' show repo;
import '../data/chains.dart';
import '../services/cloud_service.dart';
import '../services/location_service.dart';
import 'store_picker_screen.dart';
import '../util.dart';
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
                  tooltip: 'Ubicación',
                  icon: Icon(store.hasLocation ? Icons.location_on : Icons.location_off_outlined),
                  onPressed: () => showStoreLocationSheet(context, store),
                ),
                IconButton(
                  tooltip: 'Renombrar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final n = await promptText(context, title: 'Renombrar supermercado', initial: store.name);
                    if (n != null) await repo.renameStore(store.id, n);
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (a) async {
                    if (a == 'link') {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => StorePickerScreen(linkStoreId: store.id)));
                    } else if (a == 'same') {
                      await _reportSameAs(context, store);
                    } else if (a == 'delete') {
                      await _delete(context, store);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'link',
                        child: Text(store.isLinked ? 'Cambiar súper del catálogo' : 'Enlazar con el catálogo')),
                    if (store.isLinked)
                      const PopupMenuItem(value: 'same', child: Text('Avisar: está repetido en el catálogo')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: Column(children: [
                  if (store.chainKey.isNotEmpty || store.address.isNotEmpty || !store.isLinked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(children: [
                        Icon(store.isLinked ? Icons.verified_outlined : Icons.link_off,
                            size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            [
                              if (store.chainKey.isNotEmpty) chainName(store.chainKey),
                              if (store.address.isNotEmpty) store.address,
                              if (!store.isLinked) 'sin enlazar al catálogo común',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  const TabBar(tabs: [
                    Tab(text: 'Secciones'),
                    Tab(text: 'Artículos'),
                  ]),
                ]),
              ),
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

  Future<void> _delete(BuildContext context, Store store) async {
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
  }

  /// Avisa de que este súper está repetido en el catálogo común (lo revisa el administrador).
  Future<void> _reportSameAs(BuildContext context, Store store) async {
    if (!await CloudService.loggedIn()) {
      if (context.mounted) snack(context, 'Inicia sesión en Más → Cuenta y nube para avisar');
      return;
    }
    List<CatalogStore> near;
    try {
      near = await CloudService.nearbyStores(store.lat!, store.lng!, radiusKm: 0.5);
    } catch (e) {
      if (context.mounted) snack(context, '$e');
      return;
    }
    near = near.where((c) => c.id != store.globalId).toList();
    if (!context.mounted) return;
    if (near.isEmpty) {
      snack(context, 'No hay otros supermercados del catálogo a menos de 500 m');
      return;
    }
    final other = await showModalBottomSheet<CatalogStore>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('¿Con cuál está repetido?')),
          for (final c in near)
            ListTile(
              title: Text(c.name),
              subtitle: Text([chainName(c.chain), if (c.where.isNotEmpty) c.where,
                if (c.distanceKm != null) kmText(c.distanceKm!)].join(' · ')),
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    );
    if (other == null) return;
    try {
      await CloudService.reportSameAs(store.globalId!, other.id);
      if (context.mounted) snack(context, 'Gracias: se revisará y se unirán si son el mismo');
    } catch (e) {
      if (context.mounted) snack(context, '$e');
    }
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
                onReorderItem: (oldIndex, newIndex) {
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
            FutureBuilder<int>(
              future: repo.routeSamples(storeId),
              builder: (context, snap) {
                final n = snap.data ?? 0;
                if (n == 0) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Ordenar según mis compras',
                        message: 'Se reordenan las secciones según el orden en que cogiste las cosas '
                            'en $n compra(s) en esta tienda.',
                        okLabel: 'Ordenar');
                    if (!ok) return;
                    final done = await repo.applyLearnedOrder(storeId);
                    if (context.mounted) snack(context, done ? 'Secciones reordenadas' : 'Aún no hay datos suficientes');
                  },
                  icon: const Icon(Icons.route_outlined),
                  label: Text('Ordenar según mis compras ($n)'),
                );
              },
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

/// Ubicación del supermercado: necesaria para compararlo por distancia.
Future<void> showStoreLocationSheet(BuildContext context, Store store) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubicación de ${store.name}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              store.hasLocation
                  ? 'Guardada: ${store.lat!.toStringAsFixed(5)}, ${store.lng!.toStringAsFixed(5)}'
                  : 'Sin ubicación: esta tienda no entra en la comparación por distancia.',
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location),
              title: const Text('Usar mi ubicación actual'),
              subtitle: const Text('Hazlo estando dentro o en la puerta de la tienda'),
              onTap: () async {
                final pos = await LocationService.current();
                if (!ctx.mounted) return;
                if (pos == null) {
                  snack(ctx, 'No se pudo obtener la ubicación. Activa el GPS y da permiso a la app.');
                  return;
                }
                await repo.setStoreLocation(store.id, pos.lat, pos.lng);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: const Text('Escribir o pegar coordenadas'),
              subtitle: const Text('Desde Google Maps: 28.9636, -13.5477'),
              onTap: () async {
                final t = await promptText(ctx,
                    title: 'Coordenadas', hint: '28.9636, -13.5477', okLabel: 'Guardar');
                if (t == null) return;
                final c = parseCoords(t);
                if (c == null) {
                  if (ctx.mounted) snack(ctx, 'Formato no válido. Ejemplo: 28.9636, -13.5477');
                  return;
                }
                await repo.setStoreLocation(store.id, c.lat, c.lng);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            if (store.hasLocation)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_off_outlined),
                title: const Text('Quitar ubicación'),
                onTap: () async {
                  await repo.setStoreLocation(store.id, null, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
