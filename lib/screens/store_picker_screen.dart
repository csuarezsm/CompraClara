import 'package:flutter/material.dart';

import '../data/chains.dart';
import '../data/models.dart';
import '../main.dart' show repo;
import '../services/cloud_service.dart';
import '../services/location_service.dart';
import '../util.dart';
import '../widgets.dart';

/// Elegir un supermercado del catálogo común (los cercanos según el GPS) en
/// lugar de escribirlo, para que todos los usuarios usen el mismo.
///
/// Sin [linkStoreId]: añade el súper a «Mis súpers» y lo devuelve.
/// Con [linkStoreId]: enlaza ese súper local con el elegido del catálogo.
class StorePickerScreen extends StatefulWidget {
  const StorePickerScreen({super.key, this.linkStoreId});

  final String? linkStoreId;

  @override
  State<StorePickerScreen> createState() => _StorePickerScreenState();
}

class _StorePickerScreenState extends State<StorePickerScreen> {
  ({double lat, double lng})? _pos;
  List<CatalogStore> _stores = [];
  Map<String, Store> _mine = {};
  String? _error;
  bool _loading = true;
  double _radius = 3;
  String _filter = '';

  bool get _linking => widget.linkStoreId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_linking) {
      final s = await repo.storeById(widget.linkStoreId);
      if (s != null && s.hasLocation) _pos ??= (lat: s.lat!, lng: s.lng!);
    }
    _pos ??= await LocationService.current() ?? await repo.homeZone();
    final mine = <String, Store>{};
    for (final s in await repo.stores()) {
      if (s.globalId != null) mine[s.globalId!] = s;
    }
    _mine = mine;
    if (_pos == null) {
      setState(() {
        _loading = false;
        _error = 'No se pudo saber dónde estás. Activa el GPS (o fija tu zona habitual en Ajustes).';
      });
      return;
    }
    try {
      final list = await CloudService.nearbyStores(_pos!.lat, _pos!.lng, radiusKm: _radius);
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el catálogo de supermercados ($e). Puedes añadirlo a mano.';
      });
    }
  }

  String _displayName(CatalogStore c) {
    final chain = chainName(c.chain);
    final base = c.chain != 'otro' && !c.name.toLowerCase().contains(chain.toLowerCase())
        ? '$chain · ${c.name}'
        : c.name;
    final place = c.city.isNotEmpty ? c.city : c.address;
    return place.isEmpty || base.toLowerCase().contains(place.toLowerCase()) ? base : '$base ($place)';
  }

  Future<void> _pick(CatalogStore c) async {
    final existing = _mine[c.id];
    if (_linking) {
      if (existing != null && existing.id != widget.linkStoreId) {
        final merge = await confirm(context,
            title: 'Ya tienes ese súper',
            message: '«${existing.name}» ya está enlazado a este supermercado. '
                '¿Unir los dos? Precios, listas e historial pasan a «${existing.name}».',
            okLabel: 'Unir');
        if (!merge) return;
        await repo.mergeLocalStores(widget.linkStoreId!, existing.id);
        if (mounted) Navigator.pop(context, existing);
        return;
      }
      await repo.linkStore(widget.linkStoreId!,
          globalId: c.id, chainKey: c.chain, address: c.where, lat: c.lat, lng: c.lng);
      if (mounted) Navigator.pop(context, await repo.storeById(widget.linkStoreId));
      return;
    }
    if (existing != null) {
      if (mounted) {
        snack(context, 'Ya lo tenías: ${existing.name}');
        Navigator.pop(context, existing);
      }
      return;
    }
    final s = await repo.addStore(_displayName(c),
        globalId: c.id, chainKey: c.chain, address: c.where, lat: c.lat, lng: c.lng);
    if (mounted) Navigator.pop(context, s);
  }

  /// Súper que no está en el catálogo: se elige la cadena de la lista y se usa la ubicación actual.
  Future<void> _manual() async {
    var chain = 'otro';
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Añadir a mano'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                key: ValueKey(chain),
                // ignore: deprecated_member_use
                value: chain,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cadena'),
                items: [for (final e in chainNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() {
                  chain = v ?? 'otro';
                  if (name.text.trim().isEmpty && chain != 'otro') name.text = chainName(chain);
                }),
              ),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Mercadona Valterra'),
              ),
              const SizedBox(height: 8),
              Text(
                _pos == null
                    ? 'Sin ubicación: no se podrá comparar por distancia.'
                    : 'Se guarda tu ubicación actual como la del súper: hazlo estando en él.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Añadir')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final n = name.text.trim().isEmpty ? chainName(chain) : name.text.trim();
    // Con cuenta y ubicación, se da de alta en el catálogo (si ya existe, el servidor devuelve ese).
    if (_pos != null && await CloudService.loggedIn()) {
      try {
        final c = await CloudService.createStore(name: n, chain: chain, lat: _pos!.lat, lng: _pos!.lng);
        if (!mounted) return;
        await _pick(c);
        return;
      } catch (_) {
        // Sin servidor: se guarda solo en el móvil.
      }
    }
    if (_linking) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final s = await repo.addStore(n, chainKey: chain, lat: _pos?.lat, lng: _pos?.lng);
    if (mounted) {
      snack(context, 'Añadido solo en este móvil; se enlazará al catálogo al sincronizar');
      Navigator.pop(context, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _filter.trim().toLowerCase();
    final list = f.isEmpty
        ? _stores
        : _stores
            .where((s) => '${s.name} ${chainName(s.chain)} ${s.where}'.toLowerCase().contains(f))
            .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_linking ? 'Enlazar con el catálogo' : 'Añadir supermercado')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _manual,
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: const Text('No está en la lista: añadir a mano'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _linking
                        ? 'Elige cuál es este supermercado. Así sus precios se comparten con el resto de usuarios sin duplicados.'
                        : 'Elige tu supermercado de la lista de cercanos. Así todos los usuarios usan el mismo y los precios se comparan bien.',
                  ),
                ),
                if (_error != null)
                  ListTile(
                    leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.error),
                    title: Text(_error!),
                    trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
                  ),
                if (_error == null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Filtrar por cadena, nombre o calle',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No hay supermercados en el catálogo a menos de ${_radius.round()} km.',
                          textAlign: TextAlign.center),
                    ),
                  for (final c in list)
                    ListTile(
                      leading: CircleAvatar(child: Text(chainName(c.chain).characters.first)),
                      title: Text(_displayName(c)),
                      subtitle: Text([
                        if (c.distanceKm != null) kmText(c.distanceKm!),
                        if (c.where.isNotEmpty) c.where,
                        if (_mine.containsKey(c.id)) 'ya está en tus súpers',
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pick(c),
                    ),
                  if (_radius < 20)
                    TextButton.icon(
                      onPressed: () {
                        _radius = _radius < 10 ? 10 : 20;
                        _load();
                      },
                      icon: const Icon(Icons.zoom_out_map),
                      label: Text('Buscar más lejos (${_radius < 10 ? 10 : 20} km)'),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Datos de supermercados © colaboradores de OpenStreetMap.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Abre el selector y devuelve el súper añadido (o null).
Future<Store?> pickStoreFromCatalog(BuildContext context) =>
    Navigator.of(context).push<Store>(MaterialPageRoute(builder: (_) => const StorePickerScreen()));
