import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../util.dart';
import '../widgets.dart';
import 'more_screen.dart' show chooseList;

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de compras')),
      body: RepoBuilder<List<Purchase>>(
        load: () => repo.purchases(),
        builder: (context, ps) {
          if (ps.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no hay compras. Se guardan al pulsar «Terminar compra» en el modo tienda '
                  'o al leer un ticket.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: ps.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => PurchaseTile(purchase: ps[i]),
          );
        },
      ),
    );
  }
}

class PurchaseTile extends StatelessWidget {
  const PurchaseTile({super.key, required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return ListTile(
      leading: CircleAvatar(
        child: Icon(p.source == 'ticket' ? Icons.receipt_long_outlined : Icons.shopping_cart_outlined),
      ),
      title: Text(p.storeName.isEmpty ? 'Compra' : p.storeName),
      subtitle: Text([
        dateEs(p.date),
        '${p.itemsCount} artículos',
        if (p.warrantyUntil != null) 'garantía hasta ${dateEs(p.warrantyUntil!)}',
      ].join(' · ')),
      trailing: Text(money(p.total), style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: p.id)),
      ),
    );
  }
}

class PurchaseDetailScreen extends StatelessWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  Future<void> _warranty(BuildContext context, Purchase p) async {
    final now = DateTime.now();
    final initial = p.warrantyUntil == null
        ? DateTime(now.year + 3, now.month, now.day)
        : (DateTime.tryParse(p.warrantyUntil!) ?? now);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: 'Fin de la garantía',
    );
    if (d != null) await repo.updatePurchase(p.id, warrantyUntil: isoDate(d));
  }

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<({Purchase? p, List<PurchaseItem> items})>(
      load: () async => (p: await repo.purchaseById(purchaseId), items: await repo.purchaseItems(purchaseId)),
      builder: (context, d) {
        final p = d.p;
        if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Compra no encontrada')));
        final sum = d.items.fold<double>(0, (a, b) => a + (b.amount ?? 0));
        return Scaffold(
          appBar: AppBar(
            title: Text(p.storeName.isEmpty ? 'Compra' : p.storeName),
            actions: [
              IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirm(context,
                      title: 'Eliminar compra',
                      message: 'Los precios que se registraron se mantienen.',
                      okLabel: 'Eliminar');
                  if (ok) {
                    await repo.deletePurchase(p.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                title: Text(money(p.total),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text('${dateEs(p.date)} · ${p.itemsCount} artículos · '
                    '${p.source == 'ticket' ? 'desde ticket' : 'desde el modo tienda'}'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final listId = await chooseList(context, title: '¿A qué lista la añado?');
                      if (listId == null) return;
                      final n = await repo.repeatPurchase(p.id, listId);
                      if (context.mounted) snack(context, 'Añadidos $n artículos a la lista');
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Repetir compra'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _warranty(context, p),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(p.warrantyUntil == null ? 'Añadir garantía' : 'Garantía: ${dateEs(p.warrantyUntil!)}'),
                  ),
                  if (p.warrantyUntil != null)
                    TextButton(
                      onPressed: () => repo.updatePurchase(p.id, clearWarranty: true),
                      child: const Text('Quitar garantía'),
                    ),
                ]),
              ),
              if (p.imagePath != null && File(p.imagePath!).existsSync())
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Ticket')),
                        body: InteractiveViewer(child: Center(child: Image.file(File(p.imagePath!)))),
                      ),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(p.imagePath!), height: 180, fit: BoxFit.cover),
                    ),
                  ),
                ),
              const Divider(),
              for (final it in d.items)
                ListTile(
                  dense: true,
                  title: Text(it.label),
                  subtitle: Text([
                    '${qtyText(it.qty)} ud',
                    if (it.unitPrice != null) '${money(it.unitPrice)} c/u',
                    if (it.productId == null) 'sin enlazar a un artículo',
                  ].join(' · ')),
                  trailing: Text(money(it.amount)),
                ),
              if ((sum - p.total).abs() > 0.05)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Suma de líneas: ${money(sum)} (el total registrado es ${money(p.total)})',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

class WarrantiesScreen extends StatelessWidget {
  const WarrantiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Garantías')),
      body: RepoBuilder<List<Purchase>>(
        load: () async {
          final all = await repo.purchases();
          final w = all.where((p) => p.warrantyUntil != null).toList()
            ..sort((a, b) => a.warrantyUntil!.compareTo(b.warrantyUntil!));
          return w;
        },
        builder: (context, ps) {
          if (ps.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay garantías. Abre una compra del historial (por ejemplo un ticket leído '
                  'con foto) y pulsa «Añadir garantía».',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final today = todayIso();
          return ListView.separated(
            itemCount: ps.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = ps[i];
              final expired = p.warrantyUntil!.compareTo(today) < 0;
              return ListTile(
                leading: Icon(expired ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
                    color: expired ? Theme.of(context).colorScheme.error : null),
                title: Text('${p.storeName} · ${dateEs(p.date)}'),
                subtitle: Text(expired
                    ? 'Venció el ${dateEs(p.warrantyUntil!)}'
                    : 'Hasta el ${dateEs(p.warrantyUntil!)}'),
                trailing: Text(money(p.total)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: p.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
