import 'package:flutter/material.dart';

import '../data/demo.dart';
import '../main.dart' show repo;
import '../services/location_service.dart';
import '../widgets.dart';

class _SettingsData {
  _SettingsData(this.radius, this.zone);

  final double radius;
  final ({double lat, double lng})? zone;
}

/// Ajustes de comparación de precios: distancia máxima y zona habitual.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _dragging;

  Future<_SettingsData> _load() async =>
      _SettingsData(await repo.radiusKm(), await repo.homeZone());

  Future<void> _setZoneHere() async {
    final pos = await LocationService.current();
    if (!mounted) return;
    if (pos == null) {
      snack(context, 'No se pudo obtener la ubicación. Activa el GPS y da permiso a la app.');
      return;
    }
    await repo.setHomeZone(pos.lat, pos.lng);
    if (mounted) snack(context, 'Zona habitual guardada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: RepoBuilder<_SettingsData>(
        load: _load,
        builder: (context, d) {
          final radius = _dragging ?? d.radius;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Distancia máxima', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Solo se comparan los supermercados que estén a menos de esta distancia '
                'de donde estás. Así, si estás en Lanzarote no se mezclan precios de Gran Canaria.',
              ),
              const SizedBox(height: 12),
              Text('${radius.round()} km',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              Slider(
                min: 1,
                max: 100,
                divisions: 99,
                value: radius.clamp(1, 100),
                label: '${radius.round()} km',
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) async {
                  await repo.setRadiusKm(v);
                  if (mounted) setState(() => _dragging = null);
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final km in const [5, 10, 20, 40])
                    ActionChip(
                      label: Text('$km km'),
                      onPressed: () => repo.setRadiusKm(km.toDouble()),
                    ),
                ],
              ),
              const Divider(height: 40),
              Text('Zona habitual', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Se usa como punto de referencia cuando el móvil no puede dar tu ubicación '
                '(sin GPS o sin permiso). Fíjala estando en casa.',
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(d.zone == null ? Icons.location_off_outlined : Icons.home_outlined),
                title: Text(d.zone == null ? 'Sin zona habitual' : 'Zona habitual guardada'),
                subtitle: d.zone == null
                    ? null
                    : Text('${d.zone!.lat.toStringAsFixed(4)}, ${d.zone!.lng.toStringAsFixed(4)}'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _setZoneHere,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Usar mi ubicación actual'),
                  ),
                  if (d.zone != null)
                    TextButton(
                      onPressed: () => repo.setHomeZone(null, null),
                      child: const Text('Quitar'),
                    ),
                ],
              ),
              const Divider(height: 40),
              const Text(
                'Para que un supermercado entre en la comparación debe tener su ubicación guardada '
                '(en su ficha, botón de ubicación).',
              ),
              const Divider(height: 40),
              Text('Datos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: const Text('Cargar datos de ejemplo'),
                subtitle: const Text('4 supermercados ficticios (3 en Lanzarote y 1 en Gran Canaria), '
                    '26 artículos con precios y 2 listas'),
                onTap: () => loadDemoWithFeedback(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                title: const Text('Borrar todos los datos'),
                subtitle: const Text('Listas, artículos, supermercados, precios y ajustes'),
                onTap: () async {
                  final ok = await confirm(context,
                      title: 'Borrar todos los datos',
                      message: 'No se puede deshacer.',
                      okLabel: 'Borrar todo');
                  if (ok) {
                    await repo.clearAll();
                    if (context.mounted) snack(context, 'Datos borrados');
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> loadDemoWithFeedback(BuildContext context) async {
  final ok = await confirm(context,
      title: 'Cargar datos de ejemplo',
      message: 'Se añaden supermercados, artículos, precios y listas ficticios a lo que ya tengas. '
          'Puedes borrarlo todo después desde Ajustes.',
      okLabel: 'Cargar');
  if (!ok || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await loadDemoData(repo);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (context.mounted) snack(context, 'Datos de ejemplo cargados');
}
