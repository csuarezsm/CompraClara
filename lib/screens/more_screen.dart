import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../services/nearby.dart';
import '../util.dart';
import '../widgets.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'label_capture.dart';
import 'packs_screen.dart';
import 'purchases_screen.dart';
import 'settings_screen.dart';
import 'ticket_screen.dart';
import 'wallet_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _go(BuildContext context, Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget w) => ListTile(
          leading: Icon(i),
          title: Text(t),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _go(context, w),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        children: [
          const _MonthCard(),
          const _Header('Captura'),
          tile(Icons.receipt_long_outlined, 'Leer ticket', 'Foto del ticket: guarda la compra y sus precios',
              const TicketScreen()),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Leer etiqueta de estantería'),
            subtitle: const Text('Foto de la etiqueta: guarda el precio en una tienda'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => captureLabelPrice(context),
          ),
          const _Header('Compras y ahorro'),
          tile(Icons.history, 'Historial de compras', 'Cada compra con su tienda, total y artículos',
              const PurchasesScreen()),
          tile(Icons.insights_outlined, 'Resumen de gasto', 'Semana o mes: total, tiendas, secciones y ahorro',
              const SummaryScreen()),
          tile(Icons.repeat, 'Habituales', 'Lo que compras a menudo y lo que ya te toca',
              const HabitualsScreen()),
          tile(Icons.trending_down, 'Bajadas de precio', 'Artículos que compras y han bajado cerca de ti',
              const PriceDropsScreen()),
          tile(Icons.inventory_outlined, 'Packs', 'Grupos de artículos para añadir de una vez',
              const PacksScreen()),
          const _Header('Cartera'),
          tile(Icons.credit_card, 'Tarjetas de fidelidad', 'Para enseñarlas en caja', const CardsScreen()),
          tile(Icons.local_offer_outlined, 'Cupones', 'Con aviso antes de que caduquen', const CouponsScreen()),
          tile(Icons.verified_user_outlined, 'Garantías', 'Tickets guardados y plazos de garantía',
              const WarrantiesScreen()),
          const _Header('Aplicación'),
          tile(Icons.cloud_outlined, 'Cuenta y nube', 'Copia en la nube y precios compartidos con otros usuarios',
              const AccountScreen()),
          tile(Icons.palette_outlined, 'Colores y letra', 'Tema de color, claro u oscuro y tamaño de letra',
              const AppearanceScreen()),
          tile(Icons.settings_outlined, 'Ajustes', 'Distancia, presupuesto, alergias, copias y datos',
              const SettingsScreen()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      );
}

/// Gasto del mes frente al presupuesto.
class _MonthCard extends StatelessWidget {
  const _MonthCard();

  @override
  Widget build(BuildContext context) {
    return RepoBuilder<({double spent, double? budget, int coupons, int warranties})>(
      load: () async => (
        spent: await repo.spentThisMonth(),
        budget: await repo.monthlyBudget(),
        coupons: (await repo.coupons()).where((c) => (c.daysLeft ?? 99) <= 7 && (c.daysLeft ?? -1) >= 0).length,
        warranties: (await repo.warrantiesExpiring()).length,
      ),
      builder: (context, d) {
        final scheme = Theme.of(context).colorScheme;
        final ratio = d.budget == null || d.budget == 0 ? null : d.spent / d.budget!;
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gastado este mes', style: Theme.of(context).textTheme.labelLarge),
                Text(money(d.spent),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                if (ratio != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: ratio > 1 ? scheme.error : (ratio > 0.85 ? Colors.orange : scheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(ratio > 1
                      ? 'Te has pasado ${money(d.spent - d.budget!)} del presupuesto (${money(d.budget)})'
                      : 'Quedan ${money(d.budget! - d.spent)} de ${money(d.budget)}'),
                ],
                if (d.coupons > 0) Text('${d.coupons} cupón(es) caducan esta semana'),
                if (d.warranties > 0) Text('${d.warranties} garantía(s) vencen este mes'),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------- Resumen

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _month = true;
  int _offset = 0; // 0 = actual, 1 = anterior…

  ({String from, String to, String label}) _range() {
    final now = DateTime.now();
    if (_month) {
      final start = DateTime(now.year, now.month - _offset, 1);
      final end = DateTime(start.year, start.month + 1, 0);
      const months = [
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];
      return (from: isoDate(start), to: isoDate(end), label: '${months[start.month - 1]} ${start.year}');
    }
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1 + 7 * _offset));
    final sunday = monday.add(const Duration(days: 6));
    return (
      from: isoDate(monday),
      to: isoDate(sunday),
      label: 'Semana del ${dateEs(isoDate(monday))} al ${dateEs(isoDate(sunday))}'
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _range();
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen de gasto')),
      body: RepoBuilder(
        load: () async {
          final cur = await repo.summary(r.from, r.to);
          return cur;
        },
        builder: (context, s) {
          final stores = s.byStore.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final secs = s.bySection.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final maxSec = secs.isEmpty ? 1.0 : secs.first.value;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Semana')),
                  ButtonSegment(value: true, label: Text('Mes')),
                ],
                selected: {_month},
                onSelectionChanged: (v) => setState(() {
                  _month = v.first;
                  _offset = 0;
                }),
              ),
              Row(
                children: [
                  IconButton(onPressed: () => setState(() => _offset++), icon: const Icon(Icons.chevron_left)),
                  Expanded(child: Text(r.label, textAlign: TextAlign.center)),
                  IconButton(
                      onPressed: _offset == 0 ? null : () => setState(() => _offset--),
                      icon: const Icon(Icons.chevron_right)),
                ],
              ),
              Text(money(s.total),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
              Text('${s.count} compra(s)', textAlign: TextAlign.center),
              if (s.saving.abs() > 0.5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.saving > 0
                        ? 'Ahorro estimado: ${money(s.saving)} frente al precio medio de lo que compraste'
                        : 'Pagaste ${money(-s.saving)} más que el precio medio de lo que compraste',
                    textAlign: TextAlign.center,
                  ),
                ),
              const Divider(height: 32),
              Text('Por supermercado', style: Theme.of(context).textTheme.titleMedium),
              if (stores.isEmpty) const Text('Sin compras en este periodo.'),
              for (final e in stores)
                ListTile(contentPadding: EdgeInsets.zero, title: Text(e.key), trailing: Text(money(e.value))),
              const Divider(height: 32),
              Text('Por sección', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final e in secs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Expanded(child: Text(e.key)), Text(money(e.value))]),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: maxSec == 0 ? 0 : e.value / maxSec,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- Habituales

class HabitualsScreen extends StatelessWidget {
  const HabitualsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Habituales')),
      body: RepoBuilder<List<Habitual>>(
        load: repo.habituals,
        builder: (context, hs) {
          if (hs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no hay habituales. Aparecen cuando compras un artículo al menos dos veces '
                  '(al terminar una compra o al leer un ticket).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: hs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final h = hs[i];
              return ListTile(
                leading: Icon(h.isDue ? Icons.notifications_active_outlined : Icons.repeat,
                    color: h.isDue ? Theme.of(context).colorScheme.primary : null),
                title: Text(h.product.name),
                subtitle: Text([
                  'Cada ${h.everyDays!.round()} días',
                  'última hace ${h.daysSince} días',
                  if (h.isDue) 'te toca',
                ].join(' · ')),
                trailing: IconButton(
                  tooltip: 'Añadir a una lista',
                  icon: const Icon(Icons.add_shopping_cart),
                  onPressed: () async {
                    final listId = await chooseList(context);
                    if (listId == null) return;
                    await repo.addItem(listId, h.product);
                    if (context.mounted) snack(context, 'Añadido: ${h.product.name}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Elige una lista activa (o crea una). Devuelve su id.
Future<String?> chooseList(BuildContext context, {String title = '¿A qué lista?'}) async {
  final lists = await repo.lists();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final l in lists)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(l.name),
              onTap: () => Navigator.pop(ctx, l.id),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nueva lista'),
            onTap: () async {
              final n = await promptText(ctx, title: 'Nueva lista', okLabel: 'Crear');
              if (n == null) return;
              final l = await repo.createList(n);
              if (ctx.mounted) Navigator.pop(ctx, l.id);
            },
          ),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------- Bajadas de precio

class PriceDropsScreen extends StatelessWidget {
  const PriceDropsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bajadas de precio')),
      body: RepoBuilder(
        load: () async => repo.priceDrops(await nearbyStores()),
        builder: (context, drops) {
          if (drops.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay bajadas recientes en los supermercados cercanos de artículos que compras.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: drops.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = drops[i];
              final pct = ((d.before - d.now) / d.before * 100).round();
              return ListTile(
                leading: CircleAvatar(child: Text('-$pct%', style: const TextStyle(fontSize: 12))),
                title: Text(d.product.name),
                subtitle: Text('${d.store.name} · ${dateEs(d.date)}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(d.now), style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(money(d.before),
                        style: const TextStyle(decoration: TextDecoration.lineThrough, fontSize: 12)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
