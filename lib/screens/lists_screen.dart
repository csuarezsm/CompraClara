import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart' show repo;
import '../widgets.dart';
import 'list_detail_screen.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  bool _archived = false;

  Future<void> _newList() async {
    final name = await promptText(
      context,
      title: 'Nueva lista',
      hint: 'Compra semanal, barbacoa…',
      okLabel: 'Crear',
    );
    if (name == null || !mounted) return;
    final l = await repo.createList(name);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListDetailScreen(listId: l.id)),
    );
  }

  Future<void> _menu(ShoppingList l, String action) async {
    switch (action) {
      case 'rename':
        final n = await promptText(context, title: 'Renombrar lista', initial: l.name);
        if (n != null) await repo.renameList(l.id, n);
      case 'archive':
        await repo.setListArchived(l.id, !l.archived);
      case 'reuse':
        await repo.uncheckAll(l.id);
        await repo.setListArchived(l.id, false);
        if (mounted) snack(context, 'Lista restaurada con todo pendiente');
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Eliminar «${l.name}»',
          message: 'Se borrará la lista y sus artículos de la lista (el catálogo no se toca).',
          okLabel: 'Eliminar',
        );
        if (ok) await repo.deleteList(l.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_archived ? 'Listas archivadas' : 'Mis listas'),
        actions: [
          IconButton(
            tooltip: _archived ? 'Ver listas activas' : 'Ver archivadas',
            icon: Icon(_archived ? Icons.checklist : Icons.archive_outlined),
            onPressed: () => setState(() => _archived = !_archived),
          ),
        ],
      ),
      floatingActionButton: _archived
          ? null
          : FloatingActionButton.extended(
              onPressed: _newList,
              icon: const Icon(Icons.add),
              label: const Text('Nueva lista'),
            ),
      body: RepoBuilder<List<ShoppingList>>(
        load: () => repo.lists(archived: _archived),
        builder: (context, lists) {
          if (lists.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _archived
                      ? 'No hay listas archivadas.'
                      : 'Todavía no tienes listas.\nPulsa «Nueva lista» para empezar.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: lists.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = lists[i];
              final done = l.total > 0 && l.picked == l.total;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: done
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor: done
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSecondaryContainer,
                  child: Icon(done ? Icons.check : Icons.shopping_basket_outlined),
                ),
                title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(l.total == 0
                    ? 'Vacía'
                    : '${l.picked} de ${l.total} cogidos'),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) => _menu(l, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    if (l.archived)
                      const PopupMenuItem(value: 'reuse', child: Text('Restaurar y vaciar cogidos'))
                    else
                      const PopupMenuItem(value: 'archive', child: Text('Archivar')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ListDetailScreen(listId: l.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
