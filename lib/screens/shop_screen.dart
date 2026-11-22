import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../util.dart';
import '../widgets.dart';

class _ShopData {
  _ShopData({
    required this.list,
    required this.store,
    required this.groups,
    required this.prices,
  });

  final ShoppingList list;
  final Store store;
  final List<SectionGroup> groups;
  final Map<String, double> prices;

  List<ListItem> get all => groups.expand((g) => g.items).toList();
}

/// Modo supermercado: se elige la sección, se ven solo sus artículos,
/// se marcan como cogidos y se pasa a la siguiente.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.listId, required this.storeId});

  final String listId;
  final String storeId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _sel = 0;
  bool _askPrice = false;
  bool _autoAdvance = true;

  Future<_ShopData?> _load() async {
    final list = await repo.listById(widget.listId);
    final store = await repo.storeById(widget.storeId);
    if (list == null || store == null) return null;
    final groups = await repo.groups(widget.listId, store.id);
    final prices = await repo.lastPrices(store.id);
    return _ShopData(list: list, store: store, groups: groups, prices: prices);
  }

  /// Siguiente sección (a partir de la actual) que aún tenga pendientes.
  int? _nextWithPending(List<SectionGroup> groups, int from) {
    for (var step = 1; step <= groups.length; step++) {
      final i = (from + step) % groups.length;
      if (groups[i].pendingCount > 0 && i != from) return i;
    }
    return null;
  }

  Future<void> _pick(_ShopData d, SectionGroup g, ListItem it) async {
    if (_askPrice) {
      final r = await promptPrice(context,
          productName: it.name, initial: it.price ?? d.prices[it.productId]);
      if (r != null) {
        await repo.setItemPrice(it, r.price, storeId: d.store.id, offer: r.offer);
      }
    }
    await repo.setStatus(it.id, statusPicked);
    if (!mounted) return;
    if (g.pendingCount == 1) {
      final next = _nextWithPending(d.groups, _sel);
      if (next == null) {
        snack(context, 'Todo cogido. ¡Puedes terminar la compra!');
      } else if (_autoAdvance) {
        snack(context, '${g.name} completada');
        setState(() => _sel = next);
      } else {
        snack(context, '${g.name} completada');
      }
    }
  }

  Future<void> _unavailable(ListItem it) async {
    await repo.setStatus(it.id, statusUnavailable);
    if (mounted) snack(context, '${it.name}: no disponible');
  }

  Future<void> _setPrice(_ShopData d, ListItem it) async {
    final r = await promptPrice(context,
        productName: it.name, initial: it.price ?? d.prices[it.productId]);
    if (r != null) {
      await repo.setItemPrice(it, r.price, storeId: d.store.id, offer: r.offer);
    }
  }

  Future<void> _finish(_ShopData d) async {
    final all = d.all;
    final picked = all.where((i) => i.status == statusPicked).toList();
    final pending = all.where((i) => i.status == statusPending).toList();
    var total = 0.0;
    var priced = 0;
    for (final i in picked) {
      final p = i.price ?? d.prices[i.productId];
      if (p != null) {
        total += p * i.qty;
        priced++;
      }
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resumen de la compra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cogidos: ${picked.length}'),
            Text('Pendientes: ${pending.length}'),
            const SizedBox(height: 8),
            Text('Total con precio: ${money(total)}'
                '${priced < picked.length ? '  (${picked.length - priced} sin precio)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Te quedan sin coger:'),
              for (final i in pending.take(8)) Text('• ${i.name}'),
              if (pending.length > 8) Text('… y ${pending.length - 8} más'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'back'), child: const Text('Seguir')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'open'), child: const Text('Dejar abierta')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'archive'), child: const Text('Archivar lista')),
        ],
      ),
    );
    if (action == null || action == 'back' || !mounted) return;
    if (action == 'archive') await repo.setListArchived(d.list.id, true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<_ShopData?>(
      load: _load,
      builder: (context, d) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Lista no encontrada')));
        }
        final groups = d.groups;
        final all = d.all.where((i) => i.status != statusUnavailable).toList();
        final pickedAll = all.where((i) => i.status == statusPicked).length;
        final sel = groups.isEmpty ? 0 : _sel.clamp(0, groups.length - 1);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.store.name, style: const TextStyle(fontSize: 18)),
                Text('${d.list.name} · $pickedAll/${all.length} cogidos',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (a) {
                  setState(() {
                    if (a == 'price') _askPrice = !_askPrice;
                    if (a == 'auto') _autoAdvance = !_autoAdvance;
                  });
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'price',
                    checked: _askPrice,
                    child: const Text('Preguntar precio al coger'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'auto',
                    checked: _autoAdvance,
                    child: const Text('Pasar sola a la siguiente sección'),
                  ),
                ],
              ),
            ],
          ),
          body: groups.isEmpty
              ? const Center(child: Text('La lista está vacía'))
              : Column(
                  children: [
                    _SectionBar(
                      groups: groups,
                      selected: sel,
                      onSelect: (i) => setState(() => _sel = i),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _SectionBody(d: d, group: groups[sel], onPick: _pick, onUnavailable: _unavailable, onPrice: _setPrice)),
                  ],
                ),
          bottomNavigationBar: groups.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _BottomAction(
                      groups: groups,
                      selected: sel,
                      next: _nextWithPending(groups, sel),
                      onNext: (i) => setState(() => _sel = i),
                      onFinish: () => _finish(d),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.groups, required this.selected, required this.onSelect});

  final List<SectionGroup> groups;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final g = groups[i];
          final done = g.complete;
          return ChoiceChip(
            selected: i == selected,
            avatar: done ? const Icon(Icons.check_circle, size: 18) : null,
            label: Text('${g.name} ${g.pickedCount}/${g.activeCount}'),
            onSelected: (_) => onSelect(i),
          );
        },
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.d,
    required this.group,
    required this.onPick,
    required this.onUnavailable,
    required this.onPrice,
  });

  final _ShopData d;
  final SectionGroup group;
  final Future<void> Function(_ShopData, SectionGroup, ListItem) onPick;
  final Future<void> Function(ListItem) onUnavailable;
  final Future<void> Function(_ShopData, ListItem) onPrice;

  @override
  Widget build(BuildContext context) {
    final pending = group.items.where((i) => i.status == statusPending).toList();
    final picked = group.items.where((i) => i.status == statusPicked).toList();
    final unavailable = group.items.where((i) => i.status == statusUnavailable).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Sección completada',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ),
        for (final it in pending)
          Dismissible(
            key: ValueKey('p-${it.id}'),
            background: _swipeBg(context, Icons.check, 'Cogido', Alignment.centerLeft, true),
            secondaryBackground:
                _swipeBg(context, Icons.remove_shopping_cart_outlined, 'No hay', Alignment.centerRight, false),
            confirmDismiss: (dir) async {
              if (dir == DismissDirection.startToEnd) {
                await onPick(d, group, it);
              } else {
                await onUnavailable(it);
              }
              return false;
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: IconButton(
                iconSize: 32,
                icon: const Icon(Icons.radio_button_unchecked),
                onPressed: () => onPick(d, group, it),
              ),
              title: Text(it.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              subtitle: Text([
                'Cantidad: ${qtyText(it.qty)}',
                if (it.detail.isNotEmpty) it.detail,
                if (it.note.isNotEmpty) it.note,
              ].join(' · ')),
              trailing: TextButton(
                onPressed: () => onPrice(d, it),
                child: Text(
                  it.price != null
                      ? money(it.price)
                      : (d.prices[it.productId] != null ? '≈ ${money(d.prices[it.productId])}' : 'Precio'),
                ),
              ),
              onTap: () => onPick(d, group, it),
            ),
          ),
        if (picked.isNotEmpty)
          ExpansionTile(
            title: Text('Cogidos (${picked.length})'),
            children: [
              for (final it in picked)
                ListTile(
                  leading: const Icon(Icons.check_circle),
                  title: Text(it.name,
                      style: const TextStyle(decoration: TextDecoration.lineThrough)),
                  subtitle: Text('${qtyText(it.qty)} ud'
                      '${it.price != null ? ' · ${money(it.price)}' : ''}'),
                  trailing: const Text('Deshacer'),
                  onTap: () => repo.setStatus(it.id, statusPending),
                ),
            ],
          ),
        if (unavailable.isNotEmpty)
          ExpansionTile(
            title: Text('No disponibles (${unavailable.length})'),
            children: [
              for (final it in unavailable)
                ListTile(
                  leading: const Icon(Icons.remove_shopping_cart_outlined),
                  title: Text(it.name),
                  trailing: const Text('Volver a pendiente'),
                  onTap: () => repo.setStatus(it.id, statusPending),
                ),
            ],
          ),
      ],
    );
  }

  Widget _swipeBg(BuildContext context, IconData icon, String text, Alignment al, bool ok) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: ok ? scheme.primaryContainer : scheme.tertiaryContainer,
      alignment: al,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(width: 8), Text(text)],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.groups,
    required this.selected,
    required this.next,
    required this.onNext,
    required this.onFinish,
  });

  final List<SectionGroup> groups;
  final int selected;
  final int? next;
  final ValueChanged<int> onNext;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    if (next == null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: onFinish,
        icon: const Icon(Icons.done_all),
        label: const Text('Terminar compra', style: TextStyle(fontSize: 18)),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => onNext(next!),
            icon: const Icon(Icons.arrow_forward),
            label: Text('Siguiente: ${groups[next!].name}',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Terminar compra',
          onPressed: onFinish,
          icon: const Icon(Icons.done_all),
        ),
      ],
    );
  }
}
