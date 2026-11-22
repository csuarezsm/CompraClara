import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart' show repo;
import '../util.dart';
import '../widgets.dart';
import '../services/location_service.dart';
import 'add_item_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

class _DetailData {
  _DetailData({
    required this.list,
    required this.store,
    required this.groups,
    required this.estimate,
    required this.pending,
  });

  final ShoppingList list;
  final Store? store;
  final List<SectionGroup> groups;
  final ({double total, int priced, int count})? estimate;
  final int pending;
}

class ListDetailScreen extends StatelessWidget {
  const ListDetailScreen({super.key, required this.listId});

  final String listId;

  Future<_DetailData?> _load() async {
    final list = await repo.listById(listId);
    if (list == null) return null;
    final store = await repo.storeById(list.storeId);
    final groups = await repo.groups(listId, store?.id);
    final items = groups.expand((g) => g.items).toList();
    ({double total, int priced, int count})? est;
    if (store != null) {
      est = Repo.estimate(items, await repo.lastPrices(store.id));
    }
    final pending = items.where((i) => i.status == statusPending).length;
    return _DetailData(list: list, store: store, groups: groups, estimate: est, pending: pending);
  }

  Future<void> _pickStore(BuildContext context, ShoppingList list) async {
    final store = await chooseStore(context, currentId: list.storeId);
    if (store == null) return;
    await repo.setListStore(list.id, store.id == '_none' ? null : store.id);
  }

  Future<void> _go(BuildContext context, _DetailData d) async {
    var store = d.store;
    store ??= await chooseStore(context, currentId: null, forShopping: true);
    if (store == null || store.id == '_none' || !context.mounted) return;
    if (d.list.storeId != store.id) await repo.setListStore(d.list.id, store.id);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShopScreen(listId: d.list.id, storeId: store!.id),
    ));
  }

  Future<void> _compare(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final radius = await repo.radiusKm();
    var ref = await LocationService.current();
    var refLabel = 'de tu ubicación';
    if (ref == null) {
      ref = await repo.homeZone();
      refLabel = 'de tu zona habitual';
    }
    final all = await repo.compareStores(listId, lat: ref?.lat, lng: ref?.lng);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final List<StoreEstimate> ranked;
    final List<StoreEstimate> noLocation;
    var outOfRange = 0;
    if (ref == null) {
      ranked = all;
      noLocation = [];
    } else {
      ranked = all.where((e) => e.distanceKm != null && e.distanceKm! <= radius).toList();
      noLocation = all.where((e) => e.distanceKm == null).toList();
      outOfRange = all.where((e) => e.distanceKm != null && e.distanceKm! > radius).length;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Comparar supermercados', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              ref == null
                  ? 'Sin ubicación ni zona habitual: se muestran todas las tiendas. '
                      'Activa el GPS o fija tu zona para filtrar por distancia.'
                  : 'Tiendas a menos de ${radius.round()} km $refLabel, con el último precio guardado de lo pendiente.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Cambiar distancia'),
            ),
            if (ranked.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(all.isEmpty
                    ? 'Aún no hay supermercados. Añádelos en la pestaña «Súpers».'
                    : 'Ningún supermercado con ubicación dentro de ${radius.round()} km.'),
              ),
            for (var i = 0; i < ranked.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(ranked[i].store.name),
                subtitle: Text([
                  if (ranked[i].distanceKm != null) kmText(ranked[i].distanceKm!),
                  ranked[i].priced == 0
                      ? 'sin precios guardados'
                      : '${ranked[i].priced} de ${ranked[i].count} con precio',
                ].join(' · ')),
                trailing: Text(
                  ranked[i].priced == 0 ? '—' : money(ranked[i].total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (outOfRange > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$outOfRange supermercado(s) fuera del radio no se comparan.',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            if (noLocation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Sin ubicación (no se comparan): ${noLocation.map((e) => e.store.name).join(', ')}. '
                  'Guárdala en la ficha de cada supermercado.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<_DetailData?>(
      load: _load,
      builder: (context, d) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Lista no encontrada')));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(d.list.name),
            actions: [
              IconButton(
                tooltip: 'Comparar supermercados',
                icon: const Icon(Icons.compare_arrows),
                onPressed: () => _compare(context),
              ),
              PopupMenuButton<String>(
                onSelected: (a) async {
                  if (a == 'uncheck') {
                    await repo.uncheckAll(d.list.id);
                  } else if (a == 'rename') {
                    final n = await promptText(context, title: 'Renombrar lista', initial: d.list.name);
                    if (n != null) await repo.renameList(d.list.id, n);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'uncheck', child: Text('Desmarcar todo')),
                  PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddItemScreen(listId: d.list.id)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Añadir'),
          ),
          bottomNavigationBar: d.groups.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1,
                      child: FractionallySizedBox(
                        widthFactor: 0.62,
                        child: FilledButton.icon(
                          onPressed: d.pending == 0 && d.list.picked == 0 ? null : () => _go(context, d),
                          icon: const Icon(Icons.shopping_cart_checkout),
                          label: Text(d.pending == 0 ? 'Ver compra' : 'Ir de compras (${d.pending})'),
                        ),
                      ),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _Header(d: d, onStore: () => _pickStore(context, d.list)),
              if (d.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'La lista está vacía.\nPulsa «Añadir» para buscar, crear o escanear artículos.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final g in d.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    '${g.name}  ·  ${g.pickedCount}/${g.items.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                for (final it in g.items) _ItemTile(item: it, storeId: d.store?.id),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.d, required this.onStore});

  final _DetailData d;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    final est = d.estimate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.storefront, size: 18),
                label: Text(d.store?.name ?? 'Elegir supermercado'),
                onPressed: onStore,
              ),
              if (est != null && est.count > 0)
                Text(
                  est.priced == 0
                      ? 'Sin precios guardados en esta tienda'
                      : 'Estimado ${money(est.total)} (${est.priced} de ${est.count} con precio)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.storeId});

  final ListItem item;
  final String? storeId;

  @override
  Widget build(BuildContext context) {
    final picked = item.status == statusPicked;
    final unavailable = item.status == statusUnavailable;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) async {
        await repo.deleteItem(item.id);
        if (context.mounted) {
          final m = ScaffoldMessenger.of(context);
          m.hideCurrentSnackBar();
          m.showSnackBar(SnackBar(
            content: Text('Quitado: ${item.name}'),
            action: SnackBarAction(label: 'Deshacer', onPressed: () => repo.restoreItem(item)),
          ));
        }
        return false;
      },
      child: ListTile(
        leading: Checkbox(
          value: picked,
          onChanged: (v) => repo.setStatus(item.id, (v ?? false) ? statusPicked : statusPending),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            decoration: picked || unavailable ? TextDecoration.lineThrough : null,
            color: picked || unavailable ? muted : null,
          ),
        ),
        subtitle: Text([
          if (item.detail.isNotEmpty) item.detail,
          if (unavailable) 'No disponible',
          if (item.note.isNotEmpty) item.note,
        ].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: item.qty <= 1 ? null : () => repo.setQty(item.id, item.qty - 1),
            ),
            Text(qtyText(item.qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => repo.setQty(item.id, item.qty + 1),
            ),
          ],
        ),
        onLongPress: () async {
          final n = await promptText(context,
              title: 'Nota para ${item.name}', initial: item.note, hint: 'Marca, tamaño…');
          if (n != null) await repo.setNote(item.id, n);
        },
      ),
    );
  }
}

/// Selector de supermercado. Devuelve un Store con id '_none' para «sin tienda».
Future<Store?> chooseStore(
  BuildContext context, {
  String? currentId,
  bool forShopping = false,
}) async {
  final stores = await repo.stores();
  if (!context.mounted) return null;
  return showModalBottomSheet<Store>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              forShopping ? '¿En qué supermercado compras?' : 'Supermercado de esta lista',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
          ),
          for (final s in stores)
            ListTile(
              leading: Icon(s.id == currentId ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(s.name),
              onTap: () => Navigator.pop(ctx, s),
            ),
          if (!forShopping && currentId != null)
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Sin supermercado'),
              onTap: () => Navigator.pop(ctx, Store(id: '_none', name: '')),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Añadir supermercado'),
            onTap: () async {
              final name = await promptText(ctx,
                  title: 'Nuevo supermercado', hint: 'Mercadona, Hiperdino…', okLabel: 'Crear');
              if (name == null) return;
              final s = await repo.addStore(name);
              if (ctx.mounted) Navigator.pop(ctx, s);
            },
          ),
        ],
      ),
    ),
  );
}
