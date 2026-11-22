import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../widgets.dart';
import 'list_detail_screen.dart';
import 'more_screen.dart' show chooseList;

/// Packs (plantillas): grupos de artículos para añadir de una vez a una lista.
class PacksScreen extends StatelessWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final n = await promptText(context, title: 'Nuevo pack', hint: 'Desayuno, limpieza mensual…', okLabel: 'Crear');
          if (n == null) return;
          final l = await repo.createList(n, isTemplate: true);
          if (context.mounted) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListDetailScreen(listId: l.id)));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pack'),
      ),
      body: RepoBuilder<List<ShoppingList>>(
        load: () => repo.lists(templates: true),
        builder: (context, packs) {
          if (packs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Un pack es un grupo de artículos que compras juntos («desayuno», «barbacoa»). '
                  'Créalo aquí o guarda una lista como pack desde su menú.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: packs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = packs[i];
              return ListTile(
                leading: const Icon(Icons.inventory_outlined),
                title: Text(p.name),
                subtitle: Text('${p.total} artículos'),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ListDetailScreen(listId: p.id))),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) async {
                    if (a == 'add') {
                      final listId = await chooseList(context, title: '¿A qué lista añado el pack?');
                      if (listId == null) return;
                      final n = await repo.addPackToList(p.id, listId);
                      if (context.mounted) snack(context, 'Añadidos $n artículos');
                    } else if (a == 'rename') {
                      final n = await promptText(context, title: 'Renombrar pack', initial: p.name);
                      if (n != null) await repo.renameList(p.id, n);
                    } else if (a == 'delete') {
                      if (await confirm(context, title: 'Eliminar «${p.name}»', okLabel: 'Eliminar')) {
                        await repo.deleteList(p.id);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Añadir a una lista')),
                    PopupMenuItem(value: 'rename', child: Text('Renombrar')),
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

/// Selector de pack para añadirlo a la lista abierta.
Future<void> addPackDialog(BuildContext context, String listId) async {
  final packs = await repo.lists(templates: true);
  if (!context.mounted) return;
  if (packs.isEmpty) {
    snack(context, 'No tienes packs. Créalos en Más → Packs.');
    return;
  }
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Añadir un pack', style: Theme.of(ctx).textTheme.titleLarge),
        ),
        for (final p in packs)
          ListTile(
            leading: const Icon(Icons.inventory_outlined),
            title: Text(p.name),
            subtitle: Text('${p.total} artículos'),
            onTap: () => Navigator.pop(ctx, p.id),
          ),
      ]),
    ),
  );
  if (id == null) return;
  final n = await repo.addPackToList(id, listId);
  if (context.mounted) snack(context, 'Añadidos $n artículos');
}
