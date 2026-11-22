import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../services/location_service.dart';
import '../services/ocr_service.dart';
import '../util.dart';
import '../widgets.dart';
import 'list_detail_screen.dart' show chooseStore;

/// Foto de la etiqueta de estantería -> precio guardado en una tienda.
/// Si viene [item] (modo tienda), el precio se pone también en la línea.
/// Devuelve el precio guardado.
Future<double?> captureLabelPrice(
  BuildContext context, {
  Product? product,
  String? storeId,
  ListItem? item,
}) async {
  final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2000);
  if (x == null || !context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  LabelScan? scan;
  try {
    scan = await OcrService.readLabel(x.path);
  } catch (_) {
    scan = null;
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();

  var prod = product ?? (item == null ? null : await repo.productById(item.productId));
  Store? store = await repo.storeById(storeId);
  if (store == null) {
    final pos = await LocationService.current();
    if (pos != null) store = (await repo.nearestStore(pos.lat, pos.lng, maxKm: 0.4))?.store;
  }
  if (!context.mounted) return null;

  final price = TextEditingController(
      text: scan?.price == null ? '' : scan!.price!.toStringAsFixed(2).replaceAll('.', ','));
  var offer = scan?.offer ?? false;
  String? until;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Precio de la etiqueta'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (scan == null || scan.price == null)
              const Text('No se encontró el precio en la foto. Escríbelo a mano.'),
            if (scan != null && scan.name.isNotEmpty)
              Text('Texto leído: ${scan.name}', style: Theme.of(ctx).textTheme.bodySmall),
            if (scan?.unitPrice != null)
              Text('Precio por unidad leído: ${unitPriceText(scan!.unitPrice!, scan.unit)}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(prod?.name ?? 'Elegir artículo'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final p = await _pickProduct(ctx, scan?.name ?? '');
                if (p != null) setState(() => prod = p);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront),
              title: Text(store?.name ?? 'Elegir supermercado'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final s = await chooseStore(ctx, currentId: store?.id, forShopping: true);
                if (s != null && s.id != '_none') setState(() => store = s);
              },
            ),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio', suffixText: '€'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: offer,
              onChanged: (v) => setState(() => offer = v ?? false),
              title: const Text('Es oferta'),
            ),
            if (offer)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(until == null ? 'Fin de la oferta (si lo pone)' : 'Hasta el ${dateEs(until!)}'),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                      context: ctx, initialDate: now.add(const Duration(days: 7)), firstDate: now, lastDate: DateTime(now.year + 1));
                  if (d != null) setState(() => until = isoDate(d));
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
  if (res != true || !context.mounted) return null;
  final v = parseNum(price.text);
  if (v == null || prod == null || store == null) {
    snack(context, 'Falta el precio, el artículo o el supermercado');
    return null;
  }
  if (item != null) {
    await repo.setItemPrice(item, v, storeId: store!.id, offer: offer, validUntil: until, source: 'etiqueta');
  } else {
    await repo.recordPrice(prod!.id, store!.id, v, offer: offer, validUntil: until, source: 'etiqueta');
  }
  if (context.mounted) snack(context, 'Precio guardado: ${prod!.name} ${money(v)} en ${store!.name}');
  return v;
}

Future<Product?> _pickProduct(BuildContext context, String hint) async {
  final q = await promptText(context, title: 'Buscar artículo', initial: hint.split(' ').first, okLabel: 'Buscar');
  if (q == null || !context.mounted) return null;
  final ps = await repo.products(query: q);
  if (!context.mounted) return null;
  return showModalBottomSheet<Product>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: Text('Crear «$q»'),
          onTap: () async {
            final p = await repo.createProduct(name: q[0].toUpperCase() + q.substring(1));
            if (ctx.mounted) Navigator.pop(ctx, p);
          },
        ),
        for (final p in ps)
          ListTile(title: Text(p.name), subtitle: Text(p.detail), onTap: () => Navigator.pop(ctx, p)),
      ]),
    ),
  );
}
