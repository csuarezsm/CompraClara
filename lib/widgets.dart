import 'package:flutter/material.dart';

import 'data/sections.dart';
import 'main.dart' show repo;
import 'util.dart';

/// Vuelve a cargar los datos cada vez que cambia la base de datos.
class RepoBuilder<T> extends StatelessWidget {
  const RepoBuilder({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => FutureBuilder<T>(
        future: load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return builder(context, snap.data as T);
        },
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String okLabel = 'Guardar',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: Text(okLabel),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String message = '',
  String okLabel = 'Aceptar',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message.isEmpty ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
      ],
    ),
  );
  return r ?? false;
}

class PriceInput {
  PriceInput(this.price, this.offer);
  final double price;
  final bool offer;
}

Future<PriceInput?> promptPrice(
  BuildContext context, {
  required String productName,
  double? initial,
}) {
  final c = TextEditingController(text: initial == null ? '' : initial.toStringAsFixed(2).replaceAll('.', ','));
  var offer = false;
  return showDialog<PriceInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Precio de $productName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio unitario', suffixText: '€'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: offer,
              onChanged: (v) => setState(() => offer = v ?? false),
              title: const Text('Es oferta'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = parseNum(c.text);
              if (v == null || v < 0) return;
              Navigator.pop(ctx, PriceInput(v, offer));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Selector de sección general del artículo.
class SectionDropdown extends StatelessWidget {
  const SectionDropdown({super.key, required this.value, required this.onChanged, this.label = 'Sección'});

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final items = [...defaultSections];
    if (!items.contains(value)) items.add(value);
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final s in items) DropdownMenuItem(value: s, child: Text(s))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

void snack(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}
