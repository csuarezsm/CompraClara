import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../util.dart';
import '../widgets.dart';
import 'scan_screen.dart';

const _formats = {
  'ean13': 'EAN-13',
  'ean8': 'EAN-8',
  'code128': 'Code 128',
  'code39': 'Code 39',
  'qr': 'QR',
};

Barcode _barcode(String f) {
  switch (f) {
    case 'ean13':
      return Barcode.ean13();
    case 'ean8':
      return Barcode.ean8();
    case 'code39':
      return Barcode.code39();
    case 'qr':
      return Barcode.qrCode();
    default:
      return Barcode.code128();
  }
}

String _guessFormat(String code) {
  if (RegExp(r'^\d{13}$').hasMatch(code)) return 'ean13';
  if (RegExp(r'^\d{8}$').hasMatch(code)) return 'ean8';
  return 'code128';
}

// ------------------------------------------------------------- Tarjetas

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  Future<void> _edit(BuildContext context, [LoyaltyCard? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final code = TextEditingController(text: c?.code ?? '');
    var format = c?.format ?? 'code128';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? 'Nueva tarjeta' : 'Editar tarjeta'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre (tienda)'),
              ),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: 'Número de la tarjeta',
                  suffixIcon: IconButton(
                    tooltip: 'Escanear la tarjeta',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final v = await Navigator.of(ctx).push<String>(
                        MaterialPageRoute(builder: (_) => const ScanScreen(allFormats: true)),
                      );
                      if (v != null) {
                        code.text = v;
                        setState(() => format = _guessFormat(v));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(format),
                // ignore: deprecated_member_use
                value: format,
                decoration: const InputDecoration(labelText: 'Tipo de código'),
                items: [for (final e in _formats.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => format = v ?? format),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || code.text.trim().isEmpty) return;
    await repo.saveCard(id: c?.id, name: name.text.trim(), code: code.text.trim(), format: format);
  }

  void _show(BuildContext context, LoyaltyCard c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(c.name)),
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: BarcodeWidget(
              barcode: _barcode(c.format),
              data: c.code,
              height: c.format == 'qr' ? 260 : 140,
              style: const TextStyle(color: Colors.black, fontSize: 18),
              errorBuilder: (context, error) => Text('No se puede dibujar este código: $error\n\n${c.code}',
                  style: const TextStyle(color: Colors.black)),
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarjetas de fidelidad')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Añadir tarjeta'),
      ),
      body: RepoBuilder<List<LoyaltyCard>>(
        load: repo.cards,
        builder: (context, cs) {
          if (cs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Guarda aquí tus tarjetas de supermercado y enséñalas en caja desde el móvil.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: cs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = cs[i];
              return ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text(c.name),
                subtitle: Text(c.code),
                onTap: () => _show(context, c),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) async {
                    if (a == 'edit') await _edit(context, c);
                    if (a == 'delete') await repo.deleteCard(c.id);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
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

// --------------------------------------------------------------- Cupones

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  bool _showUsed = false;

  Future<void> _edit([Coupon? c]) async {
    final store = TextEditingController(text: c?.storeName ?? '');
    final desc = TextEditingController(text: c?.description ?? '');
    final code = TextEditingController(text: c?.code ?? '');
    String? expires = c?.expires;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? 'Nuevo cupón' : 'Editar cupón'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: desc,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción', hintText: '-20 % en droguería'),
              ),
              TextField(
                controller: store,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Supermercado'),
              ),
              TextField(controller: code, decoration: const InputDecoration(labelText: 'Código (opcional)')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(expires == null ? 'Sin caducidad' : 'Caduca el ${dateEs(expires!)}'),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: now.add(const Duration(days: 7)),
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (d != null) setState(() => expires = isoDate(d));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || desc.text.trim().isEmpty) return;
    await repo.saveCoupon(
      id: c?.id,
      storeName: store.text.trim(),
      description: desc.text.trim(),
      code: code.text.trim(),
      expires: expires,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cupones'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showUsed = !_showUsed),
            child: Text(_showUsed ? 'Ocultar usados' : 'Ver usados'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Añadir cupón'),
      ),
      body: RepoBuilder<List<Coupon>>(
        load: () => repo.coupons(includeUsed: _showUsed),
        builder: (context, cs) {
          if (cs.isEmpty) {
            return const Center(child: Text('No hay cupones.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: cs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = cs[i];
              final left = c.daysLeft;
              final expired = left != null && left < 0;
              final soon = left != null && left >= 0 && left <= 7;
              return ListTile(
                leading: Icon(
                  c.used ? Icons.check_circle_outline : Icons.local_offer_outlined,
                  color: expired
                      ? Theme.of(context).colorScheme.error
                      : (soon ? Colors.orange : null),
                ),
                title: Text(c.description,
                    style: TextStyle(decoration: c.used || expired ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  if (c.storeName.isNotEmpty) c.storeName,
                  if (c.code.isNotEmpty) 'Código ${c.code}',
                  if (left == null)
                    'sin caducidad'
                  else if (expired)
                    'caducado'
                  else if (left == 0)
                    'caduca hoy'
                  else
                    'caduca en $left días',
                ].join(' · ')),
                onLongPress: c.code.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: c.code));
                        snack(context, 'Código copiado');
                      },
                trailing: PopupMenuButton<String>(
                  onSelected: (a) async {
                    if (a == 'used') await repo.setCouponUsed(c.id, !c.used);
                    if (a == 'edit') await _edit(c);
                    if (a == 'delete') await repo.deleteCoupon(c.id);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'used', child: Text(c.used ? 'Marcar sin usar' : 'Marcar como usado')),
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
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
