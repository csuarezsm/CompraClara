import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart' show repo;
import '../services/location_service.dart';
import '../services/nearby.dart';
import '../util.dart';
import '../widgets.dart';
import 'add_item_screen.dart';
import 'packs_screen.dart' show addPackDialog;
import 'settings_screen.dart';
import 'shop_screen.dart';

class _DetailData {
  _DetailData({
    required this.list,
    required this.store,
    required this.groups,
    required this.estimate,
    required this.pending,
    required this.cheaper,
    required this.avoid,
    required this.diets,
    required this.monthSpent,
    required this.monthBudget,
  });

  final ShoppingList list;
  final Store? store;
  final List<SectionGroup> groups;
  final ({double total, int priced, int count})? estimate;
  final int pending;
  final Map<String, ({Store store, double price, double saving})> cheaper;
  final Set<String> avoid;
  final Set<String> diets;
  final double monthSpent;
  final double? monthBudget;
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
    var cheaper = <String, ({Store store, double price, double saving})>{};
    if (store != null && !list.isTemplate) {
      est = Repo.estimate(items, await repo.lastPrices(store.id));
      // Sin GPS aquí (solo zona habitual) para no pedir ubicación al abrir la lista.
      cheaper = await repo.cheaperElsewhere(listId, store.id, await nearbyStores(useGps: false));
    }
    final pending = items.where((i) => i.status == statusPending).length;
    return _DetailData(
      list: list,
      store: store,
      groups: groups,
      estimate: est,
      pending: pending,
      cheaper: cheaper,
      avoid: await repo.avoidAllergens(),
      diets: await repo.diets(),
      monthSpent: await repo.spentThisMonth(),
      monthBudget: await repo.monthlyBudget(),
    );
  }

  Future<void> _pickStore(BuildContext context, ShoppingList list) async {
    final store = await chooseStore(context, currentId: list.storeId);
    if (store == null) return;
    await repo.setListStore(list.id, store.id == '_none' ? null : store.id);
  }

  /// Empieza la compra; si el GPS detecta que estás en otro súper, lo propone.
  Future<void> _go(BuildContext context, _DetailData d) async {
    var store = d.store;
    final pos = await LocationService.current();
    if (pos != null && context.mounted) {
      final near = await repo.nearestStore(pos.lat, pos.lng, maxKm: 0.3);
      if (near != null && near.store.id != store?.id && context.mounted) {
        final use = await confirm(context,
            title: 'Estás en ${near.store.name}',
            message: '¿Hacer la compra en esta tienda? La lista se ordenará según sus secciones.',
            okLabel: 'Comprar aquí');
        if (use) store = near.store;
      }
    }
    if (!context.mounted) return;
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
    final ref = await referencePoint();
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
    final full = ranked.where((e) => e.count > 0 && e.priced == e.count).toList()
      ..sort((a, b) => a.total.compareTo(b.total));

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
                  ? 'Sin ubicación ni zona habitual: se muestran todas las tiendas.'
                  : 'Tiendas a menos de ${radius.round()} km ${ref.label}, con el último precio guardado de lo pendiente.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            if (full.length >= 2)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Recomendado: ${full.first.store.name}. Ahorras ${money(full[1].total - full.first.total)} '
                    'frente a ${full[1].store.name}.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
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
                      : (ranked[i].priced < ranked[i].count
                          ? '${ranked[i].priced} de ${ranked[i].count} con precio (estimación parcial)'
                          : 'todos con precio'),
                ].join(' · ')),
                trailing: Text(
                  ranked[i].priced == 0 ? '—' : money(ranked[i].total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (outOfRange > 0)
              Text('$outOfRange supermercado(s) fuera del radio no se comparan.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            if (noLocation.isNotEmpty)
              Text(
                'Sin ubicación (no se comparan): ${noLocation.map((e) => e.store.name).join(', ')}.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  /// Propone repartir la compra entre la tienda de la lista y otra cercana.
  Future<void> _split(BuildContext context, _DetailData d) async {
    if (d.store == null) {
      snack(context, 'Elige primero el supermercado de la lista');
      return;
    }
    final near = (await nearbyStores()).where((s) => s.id != d.store!.id).toList();
    if (!context.mounted) return;
    if (near.isEmpty) {
      snack(context, 'No hay otro supermercado cercano con ubicación');
      return;
    }
    final threshold = double.tryParse(await repo.getSetting('split_min') ?? '') ?? 5;
    ({Store store, double saving, int toB, int compared, List<String> itemsToB, double best})? bestPlan;
    for (final s in near) {
      final p = await repo.splitPlan(d.list.id, d.store!.id, s.id);
      final bestSingle = p.onlyA < p.onlyB ? p.onlyA : p.onlyB;
      final saving = bestSingle - (p.totalA + p.totalB);
      if (bestPlan == null || saving > bestPlan.saving) {
        bestPlan = (
          store: s,
          saving: saving,
          toB: p.toB,
          compared: p.compared,
          itemsToB: p.itemsToB,
          best: bestSingle
        );
      }
    }
    if (!context.mounted || bestPlan == null) return;
    if (bestPlan.saving < threshold || bestPlan.toB == 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dividir la compra'),
          content: Text(
            'No compensa: repartir entre dos tiendas ahorraría como mucho '
            '${money(bestPlan!.saving < 0 ? 0 : bestPlan.saving)} (mínimo configurado ${money(threshold)}).\n\n'
            'Se comparan ${bestPlan.compared} artículos con precio en ambas tiendas.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final v = await promptText(ctx,
                    title: 'Ahorro mínimo para dividir (€)', initial: threshold.toStringAsFixed(0));
                if (v != null && parseNum(v) != null) {
                  await repo.setSetting('split_min', parseNum(v)!.toStringAsFixed(2));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Cambiar mínimo'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }
    final ok = await confirm(
      context,
      title: 'Dividir la compra',
      message: 'Comprando ${bestPlan.toB} artículos en ${bestPlan.store.name} y el resto en ${d.store!.name} '
          'ahorras ${money(bestPlan.saving)}.\n\nSe creará la lista «${d.list.name} · ${bestPlan.store.name}» '
          'con esos artículos.',
      okLabel: 'Dividir',
    );
    if (!ok) return;
    final other = await repo.createList('${d.list.name} · ${bestPlan.store.name}', storeId: bestPlan.store.id);
    await repo.moveItems(bestPlan.itemsToB, other.id);
    if (context.mounted) snack(context, 'Lista creada con ${bestPlan.toB} artículos');
  }

  Future<void> _menu(BuildContext context, _DetailData d, String a) async {
    switch (a) {
      case 'uncheck':
        await repo.uncheckAll(d.list.id);
      case 'rename':
        final n = await promptText(context, title: 'Renombrar', initial: d.list.name);
        if (n != null) await repo.renameList(d.list.id, n);
      case 'budget':
        final v = await promptText(context,
            title: 'Presupuesto de esta lista (€)',
            initial: d.list.budget == null ? '' : d.list.budget!.toStringAsFixed(0),
            hint: 'Vacío = sin presupuesto');
        if (v != null) await repo.setListBudget(d.list.id, parseNum(v));
      case 'nobudget':
        await repo.setListBudget(d.list.id, null);
      case 'duplicate':
        final n = await promptText(context, title: 'Nombre de la copia', initial: '${d.list.name} (copia)');
        if (n == null) return;
        final id = await repo.duplicateList(d.list.id, name: n);
        if (context.mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ListDetailScreen(listId: id)));
        }
      case 'pack':
        final n = await promptText(context, title: 'Nombre del pack', initial: d.list.name);
        if (n == null) return;
        await repo.duplicateList(d.list.id, name: n, asTemplate: true);
        if (context.mounted) snack(context, 'Pack «$n» creado (Más → Packs)');
      case 'addpack':
        await addPackDialog(context, d.list.id);
      case 'split':
        await _split(context, d);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<_DetailData?>(
      load: _load,
      builder: (context, d) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Lista no encontrada')));
        }
        final isPack = d.list.isTemplate;
        return Scaffold(
          appBar: AppBar(
            title: Text(isPack ? 'Pack: ${d.list.name}' : d.list.name),
            actions: [
              if (!isPack)
                IconButton(
                  tooltip: 'Comparar supermercados',
                  icon: const Icon(Icons.compare_arrows),
                  onPressed: () => _compare(context),
                ),
              PopupMenuButton<String>(
                onSelected: (a) => _menu(context, d, a),
                itemBuilder: (_) => [
                  if (!isPack) const PopupMenuItem(value: 'addpack', child: Text('Añadir un pack')),
                  if (!isPack) const PopupMenuItem(value: 'split', child: Text('Dividir entre dos tiendas')),
                  if (!isPack)
                    PopupMenuItem(
                        value: 'budget',
                        child: Text(d.list.budget == null ? 'Poner presupuesto' : 'Cambiar presupuesto')),
                  if (!isPack && d.list.budget != null)
                    const PopupMenuItem(value: 'nobudget', child: Text('Quitar presupuesto')),
                  if (!isPack) const PopupMenuItem(value: 'duplicate', child: Text('Duplicar lista')),
                  if (!isPack) const PopupMenuItem(value: 'pack', child: Text('Guardar como pack')),
                  if (!isPack) const PopupMenuItem(value: 'uncheck', child: Text('Desmarcar todo')),
                  const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
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
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: d.groups.isEmpty || isPack
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 96, 8),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: d.pending == 0 && d.list.picked == 0 ? null : () => _go(context, d),
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: Text(d.pending == 0 ? 'Ver compra' : 'Ir de compras (${d.pending})'),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (!isPack) _Header(d: d, onStore: () => _pickStore(context, d.list)),
              if (d.groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    isPack
                        ? 'El pack está vacío. Pulsa «Añadir».'
                        : 'La lista está vacía.\nPulsa «Añadir» para buscar, escribir varios, dictar o escanear.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final g in d.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    isPack ? g.name : '${g.name}  ·  ${g.pickedCount}/${g.items.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                for (final it in g.items)
                  ItemTile(
                    item: it,
                    cheaper: d.cheaper[it.id],
                    warning: foodWarning(it.allergens, it.labels, d.avoid, d.diets),
                    showCheck: !isPack,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Aviso de alergia o dieta para un artículo (null si no hay nada que avisar).
String? foodWarning(String allergens, String labels, Set<String> avoid, Set<String> diets) {
  final a = allergens.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  final hit = a.intersection(avoid);
  if (hit.isNotEmpty) {
    return 'Contiene: ${hit.map((k) => allergenNames[k] ?? k).join(', ')}';
  }
  if (diets.isEmpty || labels.isEmpty) return null;
  final l = labels.split(',').map((e) => e.trim()).toSet();
  final missing = diets.where((dname) {
    if (dname == 'vegetarian' && l.contains('vegan')) return false;
    return !l.contains(dname);
  }).toList();
  if (missing.isEmpty) return null;
  return 'No consta como ${missing.map((k) => (dietNames[k] ?? k).toLowerCase()).join(', ')}';
}

class _Header extends StatelessWidget {
  const _Header({required this.d, required this.onStore});

  final _DetailData d;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    final est = d.estimate;
    final scheme = Theme.of(context).colorScheme;
    final budget = d.list.budget;
    final ratio = budget == null || est == null || budget == 0 ? null : est.total / budget;
    final monthAfter = est == null ? null : d.monthSpent + est.total;
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
                ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: ratio > 1 ? scheme.error : (ratio > 0.85 ? Colors.orange : scheme.primary),
            ),
            Text(ratio > 1
                ? 'Te pasas ${money(est!.total - budget!)} del presupuesto de la lista (${money(budget)})'
                : 'Presupuesto de la lista: ${money(budget)}'),
          ],
          if (d.monthBudget != null && monthAfter != null && monthAfter > d.monthBudget! * 0.85)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.warning_amber, size: 18, color: monthAfter > d.monthBudget! ? scheme.error : Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(monthAfter > d.monthBudget!
                      ? 'Con esta compra superarías el presupuesto del mes (${money(monthAfter)} de ${money(d.monthBudget)})'
                      : 'Con esta compra llegarías a ${money(monthAfter)} de ${money(d.monthBudget)} este mes'),
                ),
              ]),
            ),
          if (d.cheaper.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${d.cheaper.length} artículo(s) más baratos en otra tienda cercana: '
                '${money(d.cheaper.values.fold<double>(0, (a, b) => a + b.saving))} de ahorro posible.',
                style: TextStyle(color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, this.cheaper, this.warning, this.showCheck = true});

  final ListItem item;
  final ({Store store, double price, double saving})? cheaper;
  final String? warning;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final picked = item.status == statusPicked;
    final unavailable = item.status == statusUnavailable;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.5);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
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
        leading: showCheck
            ? Checkbox(
                value: picked,
                onChanged: (v) => repo.setStatus(item.id, (v ?? false) ? statusPicked : statusPending),
              )
            : const Icon(Icons.circle_outlined, size: 14),
        title: Text(
          item.name,
          style: TextStyle(
            decoration: picked || unavailable ? TextDecoration.lineThrough : null,
            color: picked || unavailable ? muted : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              if (item.detail.isNotEmpty) item.detail,
              if (item.isPartial) 'cogidos ${qtyText(item.pickedQty!)}',
              if (unavailable) 'No disponible',
              if (item.note.isNotEmpty) item.note,
            ].join(' · ')),
            if (cheaper != null && item.status == statusPending)
              Text('Más barato en ${cheaper!.store.name}: ${money(cheaper!.price)} (−${money(cheaper!.saving)})',
                  style: TextStyle(color: scheme.primary, fontSize: 12)),
            if (warning != null)
              Text(warning!, style: TextStyle(color: scheme.error, fontSize: 12)),
          ],
        ),
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
              forShopping ? '¿En qué supermercado?' : 'Supermercado de esta lista',
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
                  title: 'Nuevo supermercado', hint: 'Mercadona Arrecife', okLabel: 'Crear');
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
